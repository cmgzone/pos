import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/catalog_qr_poster_service.dart';
import '../../../core/services/catalog_share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';

class StorefrontShareDialog extends StatefulWidget {
  const StorefrontShareDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const StorefrontShareDialog(),
    );
  }

  @override
  State<StorefrontShareDialog> createState() => _StorefrontShareDialogState();
}

class _StorefrontShareDialogState extends State<StorefrontShareDialog> {
  bool _loading = true;
  bool _sharing = false;
  bool _printing = false;
  CatalogShareInfo? _info;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await CatalogShareService.prepare();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
      if (info.syncWarning != null && info.syncWarning!.isNotEmpty) {
        _showWarning(info.syncWarning!);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(Object error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppErrorMessage.from(error, fallback: fallback)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyLink() async {
    final url = _info?.url;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Store link copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openStore() async {
    final url = _info?.url;
    if (url == null || url.isEmpty) return;
    try {
      await CatalogShareService.openCatalog(_info!);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not open store link.');
    }
  }

  Future<void> _shareQrPoster() async {
    if (_info == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await CatalogQrPosterService.sharePoster(_info!);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not share QR poster.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _printQrPoster() async {
    if (_info == null || _printing) return;
    setState(() => _printing = true);
    try {
      await CatalogQrPosterService.printPoster(_info!);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not print QR poster.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width > 520 ? 480.0 : width - 32;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your Online Store',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _buildError(theme)
              else
                _buildContent(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            AppErrorMessage.from(
              _error!,
              fallback:
                  'Could not load your storefront link. Make sure cloud sync is active.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _prepare,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final url = _info?.url ?? '';
    final businessName = _info?.businessName ?? 'Your shop';

    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              businessName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Share this link or QR code so customers can browse products and place orders.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (url.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: QrImageView(
                        data: url,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  if (url.isEmpty)
                    const SizedBox(
                      height: 220,
                      child: Center(child: Text('No store link available')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: TextEditingController(text: url),
              readOnly: true,
              maxLines: 2,
              minLines: 1,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                labelText: 'Store link',
                suffixIcon: IconButton(
                  tooltip: 'Copy link',
                  onPressed: _copyLink,
                  icon: const Icon(Icons.copy_outlined),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
                OutlinedButton.icon(
                  onPressed: _openStore,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _printing ? null : _printQrPoster,
                  icon: _printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: const Text('Print poster'),
                ),
                FilledButton.icon(
                  onPressed: _sharing ? null : _shareQrPoster,
                  icon: _sharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_outlined),
                  label: const Text('Share QR poster'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
