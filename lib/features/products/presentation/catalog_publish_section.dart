import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/catalog_qr_poster_service.dart';
import '../../../core/services/catalog_share_service.dart';
import '../../../core/theme/app_colors.dart';

class CatalogPublishSection extends StatefulWidget {
  const CatalogPublishSection({super.key});

  @override
  State<CatalogPublishSection> createState() => _CatalogPublishSectionState();
}

class _CatalogPublishSectionState extends State<CatalogPublishSection> {
  bool _preparing = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width <= 720;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        12,
        isMobile ? 12 : 24,
        8,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storefront_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customer order link',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Share your catalog link or publish a QR poster for customers.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _preparing ? null : _shareCatalog,
                icon: _preparing
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_outlined, size: 18),
                label: const Text('Share Link'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _preparing ? null : _publishCatalogQr,
                icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                label: const Text('Publish QR'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<CatalogShareInfo?> _prepareCatalogShare() async {
    if (_preparing) return null;
    setState(() => _preparing = true);
    try {
      return await CatalogShareService.prepare();
    } catch (error) {
      if (!mounted) return null;
      _showActionError(context, error);
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
      }
    }
    return null;
  }

  Future<void> _shareCatalog() async {
    final info = await _prepareCatalogShare();
    if (info == null || !mounted) return;
    await _showCatalogShareDialog(info);
  }

  Future<void> _publishCatalogQr() async {
    final info = await _prepareCatalogShare();
    if (info == null || !mounted) return;
    await _showCatalogQrDialog(info);
  }

  Future<void> _showCatalogShareDialog(CatalogShareInfo info) {
    final message = CatalogShareService.buildMessage(info);
    final syncSummary = info.syncSummary;
    final syncWarning = info.syncWarning;
    final syncText = syncWarning != null
        ? 'Catalog link is ready. Latest changes could not sync: $syncWarning'
        : syncSummary == null
        ? 'Catalog link is ready.'
        : 'Synced ${syncSummary.pushedCount} local change${syncSummary.pushedCount == 1 ? '' : 's'} before sharing.';

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Share Customer Order Link'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                syncText,
                style: TextStyle(
                  color: syncWarning == null
                      ? AppColors.textSecondary
                      : AppColors.warning,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: info.url,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Customer catalog link',
                  prefixIcon: const Icon(Icons.link_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Copy link',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () => _copyLink(ctx, info.url),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: message,
                readOnly: true,
                minLines: 3,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message preview',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copyLink(ctx, info.url),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy Link'),
          ),
          OutlinedButton.icon(
            onPressed: () => _openCatalogLink(ctx, info),
            icon: const Icon(Icons.open_in_new_outlined),
            label: const Text('Open'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _showCatalogQrDialog(info);
            },
            icon: const Icon(Icons.qr_code_2_outlined),
            label: const Text('QR Poster'),
          ),
          FilledButton.icon(
            onPressed: () => _openCatalogWhatsApp(ctx, info),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Future<void> _showCatalogQrDialog(CatalogShareInfo info) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.qr_code_2_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(child: Text('Publish Catalog QR')),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Customers can scan this poster to open your catalog and place an order.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 300,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: FutureBuilder(
                    future: CatalogQrPosterService.buildPreviewPng(info),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      final preview = snapshot.data;
                      if (preview == null) {
                        return const Center(
                          child: Text('QR poster is ready to share or print.'),
                        );
                      }
                      return Image.memory(preview, fit: BoxFit.contain);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  info.url,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copyLink(ctx, info.url),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy Link'),
          ),
          OutlinedButton.icon(
            onPressed: () => _printCatalogQrPoster(ctx, info),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print'),
          ),
          FilledButton.icon(
            onPressed: () => _shareCatalogQrPoster(ctx, info),
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Share Poster'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Future<void> _copyLink(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Catalog link copied')));
  }

  Future<void> _openCatalogLink(
    BuildContext context,
    CatalogShareInfo info,
  ) async {
    try {
      await CatalogShareService.openCatalog(info);
    } catch (error) {
      if (!context.mounted) return;
      _showActionError(context, error);
    }
  }

  Future<void> _openCatalogWhatsApp(
    BuildContext context,
    CatalogShareInfo info,
  ) async {
    try {
      await CatalogShareService.openWhatsApp(info);
    } catch (error) {
      if (!context.mounted) return;
      _showActionError(context, error);
    }
  }

  Future<void> _shareCatalogQrPoster(
    BuildContext context,
    CatalogShareInfo info,
  ) async {
    try {
      await CatalogQrPosterService.sharePoster(info);
    } catch (error) {
      if (!context.mounted) return;
      _showActionError(context, error);
    }
  }

  Future<void> _printCatalogQrPoster(
    BuildContext context,
    CatalogShareInfo info,
  ) async {
    try {
      await CatalogQrPosterService.printPoster(info);
    } catch (error) {
      if (!context.mounted) return;
      _showActionError(context, error);
    }
  }

  void _showActionError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
      ),
    );
  }
}
