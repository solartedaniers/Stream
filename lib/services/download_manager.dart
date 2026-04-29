import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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

  final Map<String, ReceivePort> _receivePorts = <String, ReceivePort>{};
  final Map<String, StreamSubscription<dynamic>> _receiveSubscriptions =
      <String, StreamSubscription<dynamic>>{};

  /// Adds a remote URL download and starts its background isolate.
  Future<DownloadItem> addDownload({
    required String url,
    required DownloadItemChanged onItemChanged,
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

    final Directory appDirectory = await getApplicationDocumentsDirectory();
    final String savePath =
        '${appDirectory.path}${Platform.pathSeparator}$id$_fileSeparator$fileName';
    final ReceivePort receivePort = ReceivePort();
    _receivePorts[id] = receivePort;

    final StreamSubscription<dynamic> subscription = receivePort.listen(
      (dynamic message) {
        _handleIsolateMessage(
          item: item,
          message: message,
          onItemChanged: onItemChanged,
        );
      },
      onError: (Object error) {
        _markItemAsError(item, onItemChanged);
      },
    );
    _receiveSubscriptions[id] = subscription;

    try {
      item.status = DownloadStatus.downloading;
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
      onItemChanged(item);
      return item;
    } catch (error) {
      _markItemAsError(item, onItemChanged);
      return item;
    }
  }

  /// Adds a selected local file as an already completed item.
  DownloadItem addLocalFile(String filePath) {
    final String id = _uuid.v4();
    final String fallbackName = StringUtils.get('unknownFileName');
    final StreamController<double> streamController =
        StreamController<double>.broadcast();
    final DownloadItem item = DownloadItem(
      id: id,
      fileName: FileUtils.getFileName(filePath, fallbackName),
      url: filePath,
      progress: _completedProgress,
      status: DownloadStatus.completed,
      streamController: streamController,
      localFilePath: filePath,
      startedAt: DateTime.now(),
    );
    streamController.add(_completedProgress);
    streamController.close();
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
  void _handleIsolateMessage({
    required DownloadItem item,
    required dynamic message,
    required DownloadItemChanged onItemChanged,
  }) {
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
      item.progress = _completedProgress;
      item.status = DownloadStatus.completed;
      item.localFilePath = message[_messagePathKey] as String?;
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
}
