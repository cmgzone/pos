import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/catalog_qr_poster_service.dart';
import '../../../core/services/catalog_share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';

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
    final intro = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.apricot],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Online storefront',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Share a polished ecommerce catalog where customers browse products, add to cart, and submit orders.',
                style: TextStyle(
                  color: Color(0xC9F9F9FB),
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: isMobile ? WrapAlignment.start : WrapAlignment.end,
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
          label: const Text('Share Store Link'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _preparing ? null : _publishCatalogQr,
          icon: const Icon(Icons.qr_code_2_outlined, size: 18),
          label: const Text('QR Poster'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        12,
        isMobile ? 12 : 24,
        8,
      ),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            context.appSurfaceHighlight,
            Color(0xFF15101F),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 16), actions],
            )
          : Row(
              children: [
                Expanded(child: intro),
                const SizedBox(width: 18),
                actions,
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
      builder: (ctx) {
        final screen = MediaQuery.sizeOf(ctx);
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: const Text('Share online storefront'),
          content: SizedBox(
            width: (screen.width - 96).clamp(260.0, 520.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, color: AppColors.primary),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          info.businessName,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  syncText,
                  style: TextStyle(
                    color: syncWarning == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : AppColors.warning,
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  initialValue: info.url,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Customer catalog link',
                    prefixIcon: Icon(Icons.link_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Copy link',
                      icon: Icon(Icons.copy_outlined),
                      onPressed: () => _copyLink(ctx, info.url),
                    ),
                  ),
                ),
                SizedBox(height: 14),
                TextFormField(
                  initialValue: message,
                  readOnly: true,
                  minLines: 3,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Message preview',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actionsOverflowDirection: VerticalDirection.up,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Close'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyLink(ctx, info.url),
              icon: Icon(Icons.copy_outlined),
              label: Text('Copy Link'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openCatalogLink(ctx, info),
              icon: Icon(Icons.open_in_new_outlined),
              label: Text('Open'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _showCatalogQrDialog(info);
              },
              icon: Icon(Icons.qr_code_2_outlined),
              label: Text('QR Poster'),
            ),
            FilledButton.icon(
              onPressed: () => _openCatalogWhatsApp(ctx, info),
              icon: Icon(Icons.chat_outlined),
              label: Text('WhatsApp'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCatalogQrDialog(CatalogShareInfo info) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final screen = MediaQuery.sizeOf(ctx);
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.qr_code_2_outlined, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(child: Text('Publish Catalog QR')),
            ],
          ),
          content: SizedBox(
            width: (screen.width - 96).clamp(260.0, 420.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Customers can scan this poster to open your catalog and place an order.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 14),
                  Container(
                    height: (screen.height * 0.34).clamp(190.0, 300.0),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: FutureBuilder(
                      future: CatalogQrPosterService.buildPreviewPng(info),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        final preview = snapshot.data;
                        if (preview == null) {
                          return Center(
                            child: Text(
                              'QR poster is ready to share or print.',
                            ),
                          );
                        }
                        return Image.memory(preview, fit: BoxFit.contain);
                      },
                    ),
                  ),
                  SizedBox(height: 12),
                  SelectableText(
                    info.url,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsOverflowDirection: VerticalDirection.up,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Close'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyLink(ctx, info.url),
              icon: Icon(Icons.copy_outlined),
              label: Text('Copy Link'),
            ),
            OutlinedButton.icon(
              onPressed: () => _printCatalogQrPoster(ctx, info),
              icon: Icon(Icons.print_outlined),
              label: Text('Print'),
            ),
            FilledButton.icon(
              onPressed: () => _shareCatalogQrPoster(ctx, info),
              icon: Icon(Icons.ios_share_outlined),
              label: Text('Share Poster'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        );
      },
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
