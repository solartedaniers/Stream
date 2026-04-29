import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

import '../models/download_item.dart';
import '../services/download_manager.dart';
import '../utils/string_utils.dart';

/// Coordinates download state between the service layer and the UI.
class DownloadProvider extends ChangeNotifier {
  /// Creates the provider with its production download manager.
  DownloadProvider({DownloadManager? downloadManager})
      : _downloadManager = downloadManager ?? DownloadManager();

  static const String _downloadStartedKey = 'downloadStarted';
  static const String _downloadQueuedKey = 'downloadQueued';
  static const String _pendingDownloadsStartedKey = 'pendingDownloadsStarted';
  static const String _noPendingDownloadsKey = 'noPendingDownloads';
  static const String _invalidUrlKey = 'invalidUrl';
  static const String _emptyUrlMessageKey = 'emptyUrlMessage';
  static const String _localFileAddedKey = 'localFileAdded';
  static const String _filePickerErrorKey = 'filePickerError';
  static const String _openFileErrorKey = 'openFileError';
  static const String _downloadCancelledKey = 'downloadCancelled';

  final DownloadManager _downloadManager;
  final List<DownloadItem> _downloads = <DownloadItem>[];

  /// Immutable view of all download items.
  List<DownloadItem> get downloads => List<DownloadItem>.unmodifiable(
        _downloads,
      );

  /// Adds a new remote URL to the pending download list.
  Future<String> startDownload(String url) async {
    if (url.trim().isEmpty) {
      return _emptyUrlMessageKey;
    }

    try {
      final DownloadItem item = await _downloadManager.addDownload(
        url: url,
      );
      _downloads.insert(0, item);
      notifyListeners();
      return _downloadQueuedKey;
    } catch (error) {
      return _invalidUrlKey;
    }
  }

  /// Starts a single pending download item.
  Future<String> beginDownload(DownloadItem item) async {
    if (item.status != DownloadStatus.pending) {
      return _downloadStartedKey;
    }

    await _downloadManager.startDownload(
      item: item,
      onItemChanged: _updateItem,
    );
    notifyListeners();
    if (item.status == DownloadStatus.error) {
      return _invalidUrlKey;
    }
    return _downloadStartedKey;
  }

  /// Starts every pending download currently in the list.
  Future<String> beginPendingDownloads() async {
    final List<DownloadItem> pendingItems = _downloads
        .where((DownloadItem item) => item.status == DownloadStatus.pending)
        .toList();

    if (pendingItems.isEmpty) {
      return _noPendingDownloadsKey;
    }

    for (final DownloadItem item in pendingItems) {
      await _downloadManager.startDownload(
        item: item,
        onItemChanged: _updateItem,
      );
    }

    notifyListeners();
    return _pendingDownloadsStartedKey;
  }

  /// Opens a file picker and adds the selected local file to the list.
  Future<String> pickLocalFile() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      final List<String> selectedPaths = result?.files
              .map((PlatformFile file) => file.path)
              .whereType<String>()
              .where((String path) => path.isNotEmpty)
              .toList() ??
          <String>[];

      if (selectedPaths.isEmpty) {
        return _filePickerErrorKey;
      }

      final List<DownloadItem> selectedItems = selectedPaths
          .map((String path) => _downloadManager.addLocalFile(path))
          .toList();
      _downloads.insertAll(0, selectedItems);
      notifyListeners();
      return _localFileAddedKey;
    } catch (error) {
      return _filePickerErrorKey;
    }
  }

  /// Cancels an active download and returns a message key.
  String cancelDownload(DownloadItem item) {
    _downloadManager.cancelDownload(item);
    notifyListeners();
    return _downloadCancelledKey;
  }

  /// Opens a completed file with the operating system default app.
  Future<String?> openDownloadedFile(DownloadItem item) async {
    final String? filePath = item.localFilePath;
    if (filePath == null || filePath.isEmpty) {
      return _openFileErrorKey;
    }

    final OpenResult result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      return _openFileErrorKey;
    }

    return null;
  }

  /// Converts a download status into its localization key.
  String getStatusKey(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return 'pending';
      case DownloadStatus.downloading:
        return 'downloading';
      case DownloadStatus.completed:
        return 'completed';
      case DownloadStatus.error:
        return 'error';
    }
  }

  /// Returns a localized status label for display.
  String getStatusLabel(DownloadStatus status) {
    return StringUtils.get(getStatusKey(status));
  }

  /// Updates an existing list item when the manager reports changes.
  void _updateItem(DownloadItem changedItem) {
    final int itemIndex = _downloads.indexWhere(
      (DownloadItem item) => item.id == changedItem.id,
    );
    if (itemIndex >= 0) {
      _downloads[itemIndex] = changedItem;
    }
    notifyListeners();
  }

  /// Releases download resources when the provider is destroyed.
  @override
  void dispose() {
    _downloadManager.dispose(_downloads);
    super.dispose();
  }
}
