import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../utils/file_utils.dart';
import '../utils/string_utils.dart';

/// Displays a single download item with live progress and actions.
class DownloadTile extends StatelessWidget {
  /// Creates a download card driven by the item's progress stream.
  const DownloadTile({
    required this.item,
    required this.statusLabel,
    required this.onCancel,
    required this.onOpenFile,
    super.key,
  });

  static const double _cardRadius = 8;
  static const double _iconBoxSize = 48;
  static const double _progressHeight = 8;
  static const double _spacing = 12;
  static const double _smallSpacing = 6;
  static const int _percentageMultiplier = 100;
  static const Duration _animationDuration = Duration(milliseconds: 220);

  /// Download item rendered by this tile.
  final DownloadItem item;

  /// Localized status label provided by the state layer.
  final String statusLabel;

  /// Callback invoked when the cancel action is confirmed.
  final VoidCallback onCancel;

  /// Callback invoked when the open-file action is tapped.
  final VoidCallback onOpenFile;

  /// Builds the complete animated download tile.
  @override
  Widget build(BuildContext context) {
    final FileTypeInfo fileTypeInfo = FileUtils.getFileTypeInfo(
      item.localFilePath ?? item.fileName,
    );

    return AnimatedContainer(
      duration: _animationDuration,
      curve: Curves.easeOut,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_spacing),
          child: StreamBuilder<double>(
            stream: item.streamController.stream,
            initialData: item.progress,
            builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
              final double progress = (snapshot.data ?? item.progress)
                  .clamp(0.0, 1.0)
                  .toDouble();
              final int progressPercent =
                  (progress * _percentageMultiplier).round();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _FileIcon(info: fileTypeInfo),
                  const SizedBox(width: _spacing),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: _smallSpacing),
                        Text(
                          StringUtils.get(fileTypeInfo.labelKey),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: _spacing),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: _progressHeight,
                          borderRadius: BorderRadius.circular(_progressHeight),
                        ),
                        const SizedBox(height: _smallSpacing),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                statusLabel,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              StringUtils.format(
                                'progressPercent',
                                <String, String>{
                                  'percent': progressPercent.toString(),
                                },
                              ),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: _smallSpacing),
                        AnimatedSwitcher(
                          duration: _animationDuration,
                          child: _TileActions(
                            key: ValueKey<DownloadStatus>(item.status),
                            status: item.status,
                            onCancel: onCancel,
                            onOpenFile: onOpenFile,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Renders the file type icon in a stable square container.
class _FileIcon extends StatelessWidget {
  /// Creates a file icon using the supplied metadata.
  const _FileIcon({required this.info});

  /// Visual metadata for the icon.
  final FileTypeInfo info;

  /// Builds the colored icon box.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: DownloadTile._iconBoxSize,
      height: DownloadTile._iconBoxSize,
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DownloadTile._cardRadius),
      ),
      child: Icon(info.icon, color: info.color),
    );
  }
}

/// Shows actions that are valid for the current download state.
class _TileActions extends StatelessWidget {
  /// Creates the action row for a download tile.
  const _TileActions({
    required this.status,
    required this.onCancel,
    required this.onOpenFile,
    super.key,
  });

  /// Current item status.
  final DownloadStatus status;

  /// Callback for cancellation.
  final VoidCallback onCancel;

  /// Callback for opening a completed file.
  final VoidCallback onOpenFile;

  /// Builds the state-specific action buttons.
  @override
  Widget build(BuildContext context) {
    if (status == DownloadStatus.downloading) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          label: Text(StringUtils.get('cancel')),
        ),
      );
    }

    if (status == DownloadStatus.completed) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: onOpenFile,
          icon: const Icon(Icons.open_in_new),
          label: Text(StringUtils.get('openFile')),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
