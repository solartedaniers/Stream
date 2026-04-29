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
  static const String _downloadStartedKey = 'downloadStarted';

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
                onAddDownload: _startDownload,
                onPickFile: _pickLocalFile,
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

                    return ListView.builder(
                      semanticChildCount: provider.downloads.length,
                      itemCount: provider.downloads.length,
                      itemBuilder: (BuildContext context, int index) {
                        final DownloadItem item = provider.downloads[index];
                        return DownloadTile(
                          item: item,
                          statusLabel: provider.getStatusLabel(item.status),
                          onCancel: () => _confirmCancel(item),
                          onOpenFile: () => _openFile(item),
                        );
                      },
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

  /// Starts a remote download using the provider.
  Future<void> _startDownload() async {
    final DownloadProvider provider = context.read<DownloadProvider>();
    final String messageKey = await provider.startDownload(_urlController.text);
    if (!mounted) {
      return;
    }
    _showMessage(messageKey);
    if (messageKey == _downloadStartedKey) {
      _urlController.clear();
    }
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

/// Renders the URL input and action buttons.
class _DownloadInput extends StatelessWidget {
  /// Creates the top input area for adding downloads.
  const _DownloadInput({
    required this.controller,
    required this.onAddDownload,
    required this.onPickFile,
  });

  /// Controller for the URL input.
  final TextEditingController controller;

  /// Callback that starts a URL download.
  final VoidCallback onAddDownload;

  /// Callback that opens the local file picker.
  final VoidCallback onPickFile;

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
              tooltip: StringUtils.get('addDownload'),
              icon: const Icon(Icons.download),
            ),
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
