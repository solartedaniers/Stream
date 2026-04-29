import 'dart:async';
import 'dart:isolate';

/// Represents the lifecycle states supported by a download task.
enum DownloadStatus {
  /// The download is registered but has not emitted progress yet.
  pending,

  /// The download is actively receiving bytes from the network.
  downloading,

  /// The file has been fully downloaded or added locally.
  completed,

  /// The download failed or was cancelled.
  error,
}

/// Stores all data required to render and control a single download.
class DownloadItem {
  /// Creates a download entity with its own progress stream controller.
  DownloadItem({
    required this.id,
    required this.fileName,
    required this.url,
    required this.progress,
    required this.status,
    required this.streamController,
    required this.startedAt,
    this.isolateRef,
    this.localFilePath,
  });

  /// Unique identifier generated for the download.
  final String id;

  /// Display name derived from the URL or selected file path.
  final String fileName;

  /// Original URL used to start the download.
  final String url;

  /// Latest progress value from zero to one.
  double progress;

  /// Current lifecycle state.
  DownloadStatus status;

  /// Dedicated progress stream controller for this item.
  final StreamController<double> streamController;

  /// Background isolate handling this download, when applicable.
  Isolate? isolateRef;

  /// Saved file path available after a successful download.
  String? localFilePath;

  /// Timestamp captured when the item was created.
  final DateTime startedAt;
}
