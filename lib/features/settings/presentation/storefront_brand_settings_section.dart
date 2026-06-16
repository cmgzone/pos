import 'package:flutter/material.dart';
import '../../../core/theme/app_theme_extensions.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pos_app/core/services/catalog_share_service.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/services/storefront_brand_service.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/utils/error_messages.dart';

class StorefrontBrandSettingsSection extends StatefulWidget {
  const StorefrontBrandSettingsSection({super.key});

  @override
  State<StorefrontBrandSettingsSection> createState() =>
      _StorefrontBrandSettingsSectionState();
}

class _StorefrontBrandSettingsSectionState
    extends State<StorefrontBrandSettingsSection> {
  final _logoController = TextEditingController();
  final _coverController = TextEditingController();
  final _colorController = TextEditingController(text: '#ff2a6d');
  final _taglineController = TextEditingController(text: 'Online catalog');
  final _descriptionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;
  StorefrontBrandSettings _settings = StorefrontBrandSettings.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _coverController.dispose();
    _colorController.dispose();
    _taglineController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await StorefrontBrandService.fetchSettings();
      if (!mounted) return;
      _applySettings(settings);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not load storefront settings.');
      _applySettings(StorefrontBrandSettings.empty());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applySettings(StorefrontBrandSettings settings) {
    _settings = settings;
    _logoController.text = settings.logoUrl;
    _coverController.text = settings.coverUrl;
    _colorController.text = settings.primaryColor;
    _taglineController.text = settings.tagline;
    _descriptionController.text = settings.description;
    setState(() {});
  }

  StorefrontBrandSettings _readForm() {
    return StorefrontBrandSettings(
      businessId: _settings.businessId,
      businessName: _settings.businessName.isNotEmpty
          ? _settings.businessName
          : ShopSettings.shopName,
      logoUrl: _logoController.text.trim(),
      coverUrl: _coverController.text.trim(),
      primaryColor: _normalizeColorInput(_colorController.text),
      tagline: _taglineController.text.trim(),
      description: _descriptionController.text.trim(),
      updatedAt: _settings.updatedAt,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await StorefrontBrandService.saveSettings(_readForm());
      if (!mounted) return;
      _applySettings(saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Storefront branding saved'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not save storefront branding.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickAndUploadImage(String kind) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: kind == 'cover' ? 1800 : 900,
      maxHeight: kind == 'cover' ? 1000 : 900,
      imageQuality: 86,
    );
    if (picked == null) return;

    setState(() {
      if (kind == 'cover') {
        _uploadingCover = true;
      } else {
        _uploadingLogo = true;
      }
    });

    try {
      final url = await StorefrontBrandService.uploadImage(
        imagePath: picked.path,
        kind: kind,
      );
      if (!mounted) return;
      setState(() {
        if (kind == 'cover') {
          _coverController.text = url;
        } else {
          _logoController.text = url;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == 'cover'
                ? 'Cover photo uploaded. Save to publish it.'
                : 'Logo uploaded. Save to publish it.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not upload image.');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingCover = false;
          _uploadingLogo = false;
        });
      }
    }
  }

  Future<void> _copyStoreLink() async {
    try {
      final info = await CatalogShareService.prepare();
      await Clipboard.setData(ClipboardData(text: info.url));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Store link copied')));
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not prepare store link.');
    }
  }

  Future<void> _openStoreLink() async {
    try {
      final info = await CatalogShareService.prepare();
      await CatalogShareService.openCatalog(info);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not open store link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }

    final color = _brandColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPreview(color),
        SizedBox(height: 16),
        _buildCard([
          Text(
            'Images',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          _buildImageField(
            label: 'Logo URL',
            controller: _logoController,
            icon: Icons.storefront_outlined,
            uploadLabel: _uploadingLogo ? 'Uploading...' : 'Upload logo',
            uploading: _uploadingLogo,
            onUpload: () => _pickAndUploadImage('logo'),
          ),
          SizedBox(height: 14),
          _buildImageField(
            label: 'Cover photo URL',
            controller: _coverController,
            icon: Icons.panorama_outlined,
            uploadLabel: _uploadingCover ? 'Uploading...' : 'Upload cover',
            uploading: _uploadingCover,
            onUpload: () => _pickAndUploadImage('cover'),
          ),
          SizedBox(height: 8),
          Text(
            'Tip: use a wide cover photo and a square logo for the best catalog look.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ]),
        SizedBox(height: 16),
        _buildCard([
          Text(
            'Brand Style',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _colorController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Primary brand color',
              hintText: '#ff2a6d',
              prefixIcon: Icon(Icons.palette_outlined, color: color),
              suffixIcon: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
          ),
          SizedBox(height: 14),
          TextField(
            controller: _taglineController,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'Small headline',
              hintText: 'Online catalog',
              prefixIcon: Icon(Icons.short_text_outlined),
            ),
          ),
          SizedBox(height: 6),
          TextField(
            controller: _descriptionController,
            maxLength: 260,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Store intro text',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
        ]),
        SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _copyStoreLink,
              icon: Icon(Icons.link_outlined),
              label: Text('Copy store link'),
            ),
            OutlinedButton.icon(
              onPressed: _openStoreLink,
              icon: Icon(Icons.open_in_new_outlined),
              label: Text('Open store'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save storefront'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(Color color) {
    final logo = _logoController.text.trim();
    final cover = _coverController.text.trim();
    final title = _settings.businessName.isNotEmpty
        ? _settings.businessName
        : ShopSettings.shopName;
    return Container(
      height: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        image: _isRemoteUrl(cover)
            ? DecorationImage(
                image: NetworkImage(cover),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.45),
                  BlendMode.darken,
                ),
              )
            : null,
        gradient: _isRemoteUrl(cover)
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.65), context.appSurface],
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _isRemoteUrl(logo)
                    ? Image.network(logo, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          title.trim().isEmpty
                              ? 'P'
                              : title.trim()[0].toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          Spacer(),
          Text(
            _taglineController.text.trim().isEmpty
                ? 'Online catalog'
                : _taglineController.text.trim(),
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _descriptionController.text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildImageField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String uploadLabel,
    required bool uploading,
    required VoidCallback onUpload,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon),
              suffixIcon: controller.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: Icon(Icons.close_outlined),
                      onPressed: () => setState(controller.clear),
                    ),
            ),
          ),
        ),
        SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: uploading ? null : onUpload,
          icon: uploading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.upload_file_outlined),
          label: Text(uploadLabel),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Color get _brandColor {
    final clean = _normalizeColorInput(_colorController.text);
    final value = int.tryParse(clean.substring(1), radix: 16);
    if (value == null) return Color(0xFFff2a6d);
    return Color(value + 0xFF000000);
  }

  String _normalizeColorInput(String value) {
    final raw = value.trim();
    final withHash = raw.startsWith('#') ? raw : '#$raw';
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(withHash)) {
      return withHash.toLowerCase();
    }
    return '#ff2a6d';
  }

  bool _isRemoteUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  void _showError(Object error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppErrorMessage.from(error, fallback: fallback)),
        backgroundColor: AppColors.error,
      ),
    );
  }
}
