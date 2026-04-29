import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_item.dart';
import '../providers/download_provider.dart';
import '../utils/string_utils.dart';
import '../widgets/download_tile.dart';

/// Main screen that lets users add URLs and monitor downloads.
class HomeScreen extends StatefulWidget {
  /// Creates the download manager home screen.
  const HomeScreen({super.key});

  /// Creates the mutable state for URL input handling.
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Holds the URL text controller used by the home screen.
class _HomeScreenState extends State<HomeScreen> {
  static const double _pagePadding = 16;
  static const double _sectionSpacing = 16;
  static const double _inputSpacing = 8;
  static const double _emptyIconSize = 72;
  static const String _downloadQueuedKey = 'downloadQueued';

  final TextEditingController _urlController = TextEditingController();

  /// Releases the URL controller.
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Builds the page with input controls and the download list.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(StringUtils.get('appTitle'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_pagePadding),
          child: Column(
            children: <Widget>[
              _DownloadInput(
                controller: _urlController,
                onAddDownload: _queueDownload,
                onPickFile: _pickLocalFile,
                onStartPendingDownloads: _startPendingDownloads,
              ),
              const SizedBox(height: _sectionSpacing),
              Expanded(
                child: Consumer<DownloadProvider>(
                  builder: (
                    BuildContext context,
                    DownloadProvider provider,
                    Widget? child,
                  ) {
                    if (provider.downloads.isEmpty) {
                      return const _EmptyState();
                    }

                    final List<DownloadItem> activeItems = provider.downloads
                        .where(
                          (DownloadItem item) =>
                              item.status != DownloadStatus.completed,
                        )
                        .toList();
                    final List<DownloadItem> completedItems = provider.downloads
                        .where(
                          (DownloadItem item) =>
                              item.status == DownloadStatus.completed,
                        )
                        .toList();

                    return ListView(
                      children: <Widget>[
                        _SectionTitle(
                          title: StringUtils.get('activeDownloads'),
                        ),
                        if (activeItems.isEmpty)
                          _SectionMessage(
                            message: StringUtils.get('noPendingDownloads'),
                          )
                        else
                          ...activeItems.map(
                            (DownloadItem item) => DownloadTile(
                              item: item,
                              statusLabel: provider.getStatusLabel(
                                item.status,
                              ),
                              onStartDownload: () => _startSingleDownload(item),
                              onCancel: () => _confirmCancel(item),
                              onOpenFile: () => _openFile(item),
                            ),
                          ),
                        const SizedBox(height: _sectionSpacing),
                        _SectionTitle(
                          title: StringUtils.get('downloadedFiles'),
                        ),
                        if (completedItems.isEmpty)
                          _SectionMessage(
                            message: StringUtils.get('noDownloadedFiles'),
                          )
                        else
                          ...completedItems.map(
                            (DownloadItem item) => DownloadTile(
                              item: item,
                              statusLabel: provider.getStatusLabel(
                                item.status,
                              ),
                              onStartDownload: () => _startSingleDownload(item),
                              onCancel: () => _confirmCancel(item),
                              onOpenFile: () => _openFile(item),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adds a remote download to the pending list using the provider.
  Future<void> _queueDownload() async {
    final DownloadProvider provider = context.read<DownloadProvider>();
    final String messageKey = await provider.startDownload(_urlController.text);
    if (!mounted) {
      return;
    }
    _showMessage(messageKey);
    if (messageKey == _downloadQueuedKey) {
      _urlController.clear();
    }
  }

  /// Starts all pending downloads using their stream controllers.
  Future<void> _startPendingDownloads() async {
    final String messageKey = await context
        .read<DownloadProvider>()
        .beginPendingDownloads();
    if (!mounted) {
      return;
    }
    _showMessage(messageKey);
  }

  /// Starts one pending download from its tile action.
  Future<void> _startSingleDownload(DownloadItem item) async {
    final String messageKey = await context
        .read<DownloadProvider>()
        .beginDownload(item);
    if (!mounted) {
      return;
    }
    _showMessage(messageKey);
  }

  /// Adds a local file selected through the provider.
  Future<void> _pickLocalFile() async {
    final DownloadProvider provider = context.read<DownloadProvider>();
    final String messageKey = await provider.pickLocalFile();
    if (!mounted) {
      return;
    }
    _showMessage(messageKey);
  }

  /// Confirms and cancels an active download.
  Future<void> _confirmCancel(DownloadItem item) async {
    final bool? shouldCancel = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(StringUtils.get('confirmCancelTitle')),
          content: Text(StringUtils.get('cancelConfirm')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(StringUtils.get('no')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(StringUtils.get('yes')),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldCancel != true) {
      return;
    }

    final String messageKey = context.read<DownloadProvider>().cancelDownload(
          item,
        );
    _showMessage(messageKey);
  }

  /// Opens the completed file associated with a download.
  Future<void> _openFile(DownloadItem item) async {
    final String? messageKey = await context
        .read<DownloadProvider>()
        .openDownloadedFile(item);
    if (!mounted || messageKey == null) {
      return;
    }
    _showMessage(messageKey);
  }

  /// Shows a localized snackbar message.
  void _showMessage(String messageKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(StringUtils.get(messageKey))),
    );
  }
}

/// Renders a compact title for a download list section.
class _SectionTitle extends StatelessWidget {
  /// Creates a section title.
  const _SectionTitle({required this.title});

  /// Localized section title.
  final String title;

  /// Builds the title text.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _HomeScreenState._inputSpacing),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// Renders a short message inside an empty section.
class _SectionMessage extends StatelessWidget {
  /// Creates a section empty message.
  const _SectionMessage({required this.message});

  /// Localized section message.
  final String message;

  /// Builds the message text.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: _HomeScreenState._inputSpacing,
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Renders the URL input and action buttons.
class _DownloadInput extends StatelessWidget {
  /// Creates the top input area for adding downloads.
  const _DownloadInput({
    required this.controller,
    required this.onAddDownload,
    required this.onPickFile,
    required this.onStartPendingDownloads,
  });

  /// Controller for the URL input.
  final TextEditingController controller;

  /// Callback that starts a URL download.
  final VoidCallback onAddDownload;

  /// Callback that opens the local file picker.
  final VoidCallback onPickFile;

  /// Callback that starts every pending download.
  final VoidCallback onStartPendingDownloads;

  /// Builds the input controls.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onAddDownload(),
          decoration: InputDecoration(
            labelText: StringUtils.get('urlFieldLabel'),
            hintText: StringUtils.get('urlHint'),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: onAddDownload,
              tooltip: StringUtils.get('addToList'),
              icon: const Icon(Icons.playlist_add),
            ),
          ),
        ),
        const SizedBox(height: _HomeScreenState._inputSpacing),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStartPendingDownloads,
            icon: const Icon(Icons.download),
            label: Text(StringUtils.get('startPendingDownloads')),
          ),
        ),
        const SizedBox(height: _HomeScreenState._inputSpacing),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(StringUtils.get('pickFile')),
          ),
        ),
      ],
    );
  }
}

/// Shows the empty list message.
class _EmptyState extends StatelessWidget {
  /// Creates the empty state widget.
  const _EmptyState();

  /// Builds the empty state content.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.cloud_download_outlined,
            size: _HomeScreenState._emptyIconSize,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: _HomeScreenState._inputSpacing),
          Text(
            StringUtils.get('noDownloads'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
