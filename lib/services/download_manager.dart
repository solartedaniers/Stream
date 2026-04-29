import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/download_item.dart';
import '../utils/file_utils.dart';
import '../utils/string_utils.dart';

/// Signature used to report item changes back to the state provider.
typedef DownloadItemChanged = void Function(DownloadItem item);

/// Creates downloads, owns progress controllers, and runs HTTP work in isolates.
class DownloadManager {
  static const Uuid _uuid = Uuid();
  static const int _httpTimeoutSeconds = 45;
  static const int _successStatusMin = 200;
  static const int _successStatusMax = 299;
  static const double _completedProgress = 1.0;
  static const double _initialProgress = 0.0;
  static const String _messageTypeKey = 'type';
  static const String _messageProgressKey = 'progress';
  static const String _messagePathKey = 'path';
  static const String _messageErrorKey = 'error';
  static const String _progressMessage = 'progress';
  static const String _completedMessage = 'completed';
  static const String _errorMessage = 'error';
  static const String _httpScheme = 'http';
  static const String _httpsScheme = 'https';
  static const String _oneDriveHost = 'onedrive.live.com';
  static const String _shortOneDriveHost = '1drv.ms';
  static const String _oneDriveRedirectionToken = 'redir?';
  static const String _oneDriveDownloadToken = 'download?';
  static const String _downloadParameter = 'download';
  static const String _downloadParameterValue = '1';
  static const String _fileSeparator = '-';
  static const int _copyBufferSize = 65536;
  static const String _storageChannelName = 'download_manager/storage';
  static const String _publishFileMethod = 'publishFileToDownloads';
  static const String _sourcePathArgument = 'sourcePath';
  static const String _fileNameArgument = 'fileName';

  static const MethodChannel _storageChannel = MethodChannel(
    _storageChannelName,
  );

  final Map<String, ReceivePort> _receivePorts = <String, ReceivePort>{};
  final Map<String, StreamSubscription<dynamic>> _receiveSubscriptions =
      <String, StreamSubscription<dynamic>>{};

  /// Adds a remote URL download as a pending item with its own stream.
  Future<DownloadItem> addDownload({
    required String url,
  }) async {
    final Uri? parsedUri = Uri.tryParse(url.trim());
    if (!_isSupportedUri(parsedUri)) {
      throw ArgumentError(StringUtils.get('invalidUrl'));
    }

    final String resolvedUrl = resolveDownloadUrl(url.trim());
    final String id = _uuid.v4();
    final String fallbackName = StringUtils.get('unknownFileName');
    final String fileName = FileUtils.getFileName(resolvedUrl, fallbackName);
    final StreamController<double> streamController =
        StreamController<double>.broadcast();
    final DownloadItem item = DownloadItem(
      id: id,
      fileName: fileName,
      url: url.trim(),
      progress: _initialProgress,
      status: DownloadStatus.pending,
      streamController: streamController,
      startedAt: DateTime.now(),
    );

    return item;
  }

  /// Starts the background isolate for a pending download item.
  Future<void> startDownload({
    required DownloadItem item,
    required DownloadItemChanged onItemChanged,
  }) async {
    if (item.status != DownloadStatus.pending) {
      return;
    }

    final String resolvedUrl = resolveDownloadUrl(item.url);
    final String savePath = await _buildTemporarySavePath(item);
    final ReceivePort receivePort = ReceivePort();
    _receivePorts[item.id] = receivePort;

    final StreamSubscription<dynamic> subscription = receivePort.listen(
      (dynamic message) async {
        await _handleIsolateMessage(
          item: item,
          message: message,
          onItemChanged: onItemChanged,
        );
      },
      onError: (Object error) {
        _markItemAsError(item, onItemChanged);
      },
    );
    _receiveSubscriptions[item.id] = subscription;

    try {
      item.status = DownloadStatus.downloading;
      if (_isSupportedUri(Uri.tryParse(item.url))) {
        item.isolateRef = await Isolate.spawn<Map<String, dynamic>>(
          _downloadTask,
          <String, dynamic>{
            'url': resolvedUrl,
            'sendPort': receivePort.sendPort,
            'savePath': savePath,
          },
          onError: receivePort.sendPort,
          onExit: receivePort.sendPort,
        );
      } else {
        item.isolateRef = await Isolate.spawn<Map<String, dynamic>>(
          _copyFileTask,
          <String, dynamic>{
            'sourcePath': item.url,
            'sendPort': receivePort.sendPort,
            'savePath': savePath,
          },
          onError: receivePort.sendPort,
          onExit: receivePort.sendPort,
        );
      }
      onItemChanged(item);
    } catch (error) {
      _markItemAsError(item, onItemChanged);
    }
  }

  /// Adds a selected local file as a pending item ready to be copied.
  DownloadItem addLocalFile(String filePath) {
    final String id = _uuid.v4();
    final String fallbackName = StringUtils.get('unknownFileName');
    final StreamController<double> streamController =
        StreamController<double>.broadcast();
    final DownloadItem item = DownloadItem(
      id: id,
      fileName: FileUtils.getFileName(filePath, fallbackName),
      url: filePath,
      progress: _initialProgress,
      status: DownloadStatus.pending,
      streamController: streamController,
      startedAt: DateTime.now(),
    );
    return item;
  }

  /// Cancels a running download and releases its resources.
  void cancelDownload(DownloadItem item) {
    item.status = DownloadStatus.error;
    item.isolateRef?.kill(priority: Isolate.immediate);
    item.isolateRef = null;
    _closeItemResources(item);
  }

  /// Converts OneDrive share URLs into direct download URLs when possible.
  String resolveDownloadUrl(String url) {
    final Uri? parsedUri = Uri.tryParse(url);
    if (parsedUri == null) {
      return url;
    }

    final bool isOneDriveUrl =
        parsedUri.host.contains(_oneDriveHost) ||
        parsedUri.host.contains(_shortOneDriveHost);
    if (!isOneDriveUrl) {
      return url;
    }

    if (url.contains(_oneDriveRedirectionToken)) {
      return url.replaceFirst(_oneDriveRedirectionToken, _oneDriveDownloadToken);
    }

    if (parsedUri.queryParameters[_downloadParameter] ==
        _downloadParameterValue) {
      return url;
    }

    return parsedUri
        .replace(
          queryParameters: <String, String>{
            ...parsedUri.queryParameters,
            _downloadParameter: _downloadParameterValue,
          },
        )
        .toString();
  }

  /// Closes all controllers, ports, subscriptions, and isolates.
  void dispose(List<DownloadItem> items) {
    for (final DownloadItem item in items) {
      item.isolateRef?.kill(priority: Isolate.immediate);
      item.isolateRef = null;
      _closeItemResources(item);
    }
    _receivePorts.clear();
    _receiveSubscriptions.clear();
  }

  /// Handles structured messages emitted by a download isolate.
  Future<void> _handleIsolateMessage({
    required DownloadItem item,
    required dynamic message,
    required DownloadItemChanged onItemChanged,
  }) async {
    if (message is List<dynamic>) {
      _markItemAsError(item, onItemChanged);
      return;
    }

    if (message is! Map) {
      return;
    }

    final Object? messageType = message[_messageTypeKey];
    if (messageType == _progressMessage) {
      final double progress = (message[_messageProgressKey] as num)
          .toDouble()
          .clamp(_initialProgress, _completedProgress)
          .toDouble();
      item.progress = progress;
      item.status = DownloadStatus.downloading;
      if (!item.streamController.isClosed) {
        item.streamController.sink.add(progress);
      }
      onItemChanged(item);
      return;
    }

    if (messageType == _completedMessage) {
      final String temporaryPath = message[_messagePathKey] as String;
      final String publishedPath = await _publishFileToDeviceDownloads(
        temporaryPath: temporaryPath,
        fileName: item.fileName,
      );
      item.progress = _completedProgress;
      item.status = DownloadStatus.completed;
      item.localFilePath = publishedPath;
      if (!item.streamController.isClosed) {
        item.streamController.sink.add(_completedProgress);
      }
      _closeItemResources(item);
      onItemChanged(item);
      return;
    }

    if (messageType == _errorMessage) {
      _markItemAsError(item, onItemChanged);
    }
  }

  /// Marks an item as failed and releases resources.
  void _markItemAsError(
    DownloadItem item,
    DownloadItemChanged onItemChanged,
  ) {
    item.status = DownloadStatus.error;
    if (!item.streamController.isClosed) {
      item.streamController.addError(StringUtils.get('error'));
    }
    _closeItemResources(item);
    onItemChanged(item);
  }

  /// Releases resources associated with a single item.
  void _closeItemResources(DownloadItem item) {
    item.isolateRef?.kill(priority: Isolate.immediate);
    item.isolateRef = null;
    _receiveSubscriptions.remove(item.id)?.cancel();
    _receivePorts.remove(item.id)?.close();
    if (!item.streamController.isClosed) {
      item.streamController.close();
    }
  }

  /// Builds the temporary path used by isolates before public publishing.
  Future<String> _buildTemporarySavePath(DownloadItem item) async {
    final Directory saveDirectory = await getTemporaryDirectory();
    await saveDirectory.create(recursive: true);
    return '${saveDirectory.path}${Platform.pathSeparator}${item.id}$_fileSeparator${item.fileName}';
  }

  /// Publishes a completed temporary file to the device Downloads folder.
  Future<String> _publishFileToDeviceDownloads({
    required String temporaryPath,
    required String fileName,
  }) async {
    try {
      final String? publishedPath = await _storageChannel.invokeMethod<String>(
        _publishFileMethod,
        <String, String>{
          _sourcePathArgument: temporaryPath,
          _fileNameArgument: fileName,
        },
      );

      if (publishedPath != null && publishedPath.isNotEmpty) {
        return publishedPath;
      }
    } catch (_) {
      // Keep the temporary file path if the platform cannot publish publicly.
    }

    return temporaryPath;
  }

  /// Checks whether a URI can be downloaded by this manager.
  bool _isSupportedUri(Uri? uri) {
    if (uri == null) {
      return false;
    }
    return uri.scheme == _httpScheme || uri.scheme == _httpsScheme;
  }

  /// Downloads a file in a background isolate and reports progress by port.
  @pragma('vm:entry-point')
  static Future<void> _downloadTask(Map<String, dynamic> arguments) async {
    final String url = arguments['url'] as String;
    final SendPort sendPort = arguments['sendPort'] as SendPort;
    final String savePath = arguments['savePath'] as String;
    final http.Client client = http.Client();

    try {
      final http.Request request = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse response = await client
          .send(request)
          .timeout(const Duration(seconds: _httpTimeoutSeconds));

      if (response.statusCode < _successStatusMin ||
          response.statusCode > _successStatusMax) {
        throw HttpException(response.statusCode.toString());
      }

      final File outputFile = File(savePath);
      await outputFile.parent.create(recursive: true);
      final IOSink outputSink = outputFile.openWrite();
      final int? contentLength = response.contentLength;
      int receivedBytes = 0;

      await for (final List<int> chunk in response.stream) {
        receivedBytes += chunk.length;
        outputSink.add(chunk);

        if (contentLength != null && contentLength > 0) {
          final double progress = receivedBytes / contentLength;
          sendPort.send(<String, dynamic>{
            _messageTypeKey: _progressMessage,
            _messageProgressKey: progress,
          });
        }
      }

      await outputSink.flush();
      await outputSink.close();
      sendPort.send(<String, dynamic>{
        _messageTypeKey: _completedMessage,
        _messagePathKey: savePath,
      });
    } catch (error) {
      sendPort.send(<String, dynamic>{
        _messageTypeKey: _errorMessage,
        _messageErrorKey: error.toString(),
      });
    } finally {
      client.close();
    }
  }

  /// Copies a local file in a background isolate and reports progress by port.
  @pragma('vm:entry-point')
  static Future<void> _copyFileTask(Map<String, dynamic> arguments) async {
    final String sourcePath = arguments['sourcePath'] as String;
    final SendPort sendPort = arguments['sendPort'] as SendPort;
    final String savePath = arguments['savePath'] as String;

    RandomAccessFile? sourceFile;
    IOSink? outputSink;

    try {
      final File inputFile = File(sourcePath);
      if (!await inputFile.exists()) {
        throw FileSystemException('Source file not found', sourcePath);
      }

      final File outputFile = File(savePath);
      await outputFile.parent.create(recursive: true);

      final int totalBytes = await inputFile.length();
      int copiedBytes = 0;
      sourceFile = await inputFile.open();
      outputSink = outputFile.openWrite();

      while (copiedBytes < totalBytes) {
        final int remainingBytes = totalBytes - copiedBytes;
        final int readLength = remainingBytes < _copyBufferSize
            ? remainingBytes
            : _copyBufferSize;
        final List<int> chunk = await sourceFile.read(readLength);
        if (chunk.isEmpty) {
          break;
        }

        copiedBytes += chunk.length;
        outputSink.add(chunk);

        final double progress = totalBytes == 0
            ? _completedProgress
            : copiedBytes / totalBytes;
        sendPort.send(<String, dynamic>{
          _messageTypeKey: _progressMessage,
          _messageProgressKey: progress,
        });
      }

      await outputSink.flush();
      await outputSink.close();
      outputSink = null;
      await sourceFile.close();
      sourceFile = null;

      sendPort.send(<String, dynamic>{
        _messageTypeKey: _completedMessage,
        _messagePathKey: savePath,
      });
    } catch (error) {
      sendPort.send(<String, dynamic>{
        _messageTypeKey: _errorMessage,
        _messageErrorKey: error.toString(),
      });
    } finally {
      await outputSink?.close();
      await sourceFile?.close();
    }
  }
}
