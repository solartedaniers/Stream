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

  /// Starts a new remote download from a URL and returns a message key.
  Future<String> startDownload(String url) async {
    if (url.trim().isEmpty) {
      return _emptyUrlMessageKey;
    }

    try {
      final DownloadItem item = await _downloadManager.addDownload(
        url: url,
        onItemChanged: _updateItem,
      );
      _downloads.insert(0, item);
      notifyListeners();
      return _downloadStartedKey;
    } catch (error) {
      return _invalidUrlKey;
    }
  }

  /// Opens a file picker and adds the selected local file to the list.
  Future<String> pickLocalFile() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles();
      final String? path = result?.files.single.path;
      if (path == null || path.isEmpty) {
        return _filePickerErrorKey;
      }

      final DownloadItem item = _downloadManager.addLocalFile(path);
      _downloads.insert(0, item);
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
