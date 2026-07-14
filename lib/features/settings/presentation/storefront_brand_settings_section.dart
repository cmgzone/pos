import 'package:flutter/material.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../widgets/stitch_kit.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pos_app/core/services/branch_service.dart';
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
  static const _brandColorPresets = [
    '#ff2a6d',
    '#f4c430',
    '#10b981',
    '#0ea5e9',
    '#6366f1',
    '#8b5cf6',
    '#ef4444',
    '#f97316',
    '#14b8a6',
    '#111827',
  ];

  final _logoController = TextEditingController();
  final _coverController = TextEditingController();
  final _colorController = TextEditingController(text: '#ff2a6d');
  final _taglineController = TextEditingController(text: 'Online catalog');
  final _descriptionController = TextEditingController();
  final _nameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;
  List<String> _coverUrls = [];
  List<Map<String, dynamic>> _branches = [];
  String _selectedBranchId = 'main_branch';
  StorefrontBrandSettings _settings = StorefrontBrandSettings.empty();

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _coverController.dispose();
    _colorController.dispose();
    _taglineController.dispose();
    _descriptionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      _branches = await BranchService.getBranches(activeOnly: true);
    } catch (_) {
      _branches = [];
    }
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await StorefrontBrandService.fetchSettings(
        branchId: _selectedBranchId,
      );
      if (!mounted) return;
      _applySettings(settings);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not load storefront settings.');
      _applySettings(
        StorefrontBrandSettings.empty(branchId: _selectedBranchId),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applySettings(StorefrontBrandSettings settings) {
    _settings = settings;
    _selectedBranchId = settings.branchId.isNotEmpty
        ? settings.branchId
        : 'main_branch';
    _nameController.text = settings.businessName;
    _logoController.text = settings.logoUrl;
    _coverUrls = settings.coverUrls.isNotEmpty
        ? List<String>.from(settings.coverUrls)
        : settings.coverUrl.trim().isNotEmpty
        ? [settings.coverUrl.trim()]
        : [];
    _coverController.clear();
    _colorController.text = settings.primaryColor;
    _taglineController.text = settings.tagline;
    _descriptionController.text = settings.description;
    setState(() {});
  }

  StorefrontBrandSettings _readForm() {
    final coverUrls = _normalizedCoverUrls();
    return StorefrontBrandSettings(
      businessId: _settings.businessId,
      businessName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : ShopSettings.shopName,
      branchId: _selectedBranchId,
      logoUrl: _logoController.text.trim(),
      coverUrl: coverUrls.isNotEmpty ? coverUrls.first : '',
      coverUrls: coverUrls,
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
      if (kind == 'cover') {
        _addCoverUrl(url, showMessage: false);
      } else {
        setState(() {
          _logoController.text = url;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == 'cover'
                ? 'Store photo uploaded. Save to publish the slideshow.'
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
        if (_branches.length > 1)
          _buildCard([
            Text(
              'Storefront branch',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Edit branding for branch',
                prefixIcon: Icon(Icons.store_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _branches.any((b) => b['id'] == _selectedBranchId)
                      ? _selectedBranchId
                      : _branches.first['id']?.toString() ?? _selectedBranchId,
                  items: _branches.map((branch) {
                    final id = branch['id']?.toString() ?? '';
                    final name = branch['name']?.toString() ?? id;
                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null || value == _selectedBranchId) return;
                    setState(() => _selectedBranchId = value);
                    _load();
                  },
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _selectedBranchId == 'main_branch'
                  ? 'This is the default storefront branding shared when a branch has no custom branding.'
                  : 'These settings apply only to the selected branch’s online store.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ]),
        if (_branches.length > 1) SizedBox(height: 16),
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
          _buildCoverGalleryField(),
          SizedBox(height: 8),
          Text(
            'Tip: add 3-5 wide photos of your shop, service bay, seats, team, or finished work. The first photo appears as the main cover.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
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
            controller: _nameController,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Store name',
              hintText: ShopSettings.shopName,
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          SizedBox(height: 14),
          _buildColorPickerField(color),
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
    final coverUrls = _normalizedCoverUrls();
    final cover = coverUrls.isNotEmpty ? coverUrls.first : '';
    final title = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
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
          if (coverUrls.length > 1) ...[
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${coverUrls.length} slideshow photos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
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

  Widget _buildColorPickerField(Color color) {
    final input = TextField(
      controller: _colorController,
      onChanged: (_) => setState(() {}),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
        LengthLimitingTextInputFormatter(7),
      ],
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
    );
    final pickButton = OutlinedButton.icon(
      onPressed: _openColorPicker,
      icon: Icon(Icons.color_lens_outlined),
      label: Text('Pick color'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [input, SizedBox(height: 10), pickButton],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: input),
            SizedBox(width: 10),
            pickButton,
          ],
        );
      },
    );
  }

  Future<void> _openColorPicker() async {
    var selectedHex = _normalizeColorInput(_colorController.text);
    var red = _hexChannel(selectedHex, 0);
    var green = _hexChannel(selectedHex, 1);
    var blue = _hexChannel(selectedHex, 2);

    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateFromRgb() {
              selectedHex = _hexFromRgb(red, green, blue);
            }

            void setSelectedHex(String hex) {
              selectedHex = _normalizeColorInput(hex);
              red = _hexChannel(selectedHex, 0);
              green = _hexChannel(selectedHex, 1);
              blue = _hexChannel(selectedHex, 2);
            }

            Widget channelSlider({
              required String label,
              required int value,
              required Color activeColor,
              required ValueChanged<int> onChanged,
            }) {
              return Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      label,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 255,
                      divisions: 255,
                      value: value.toDouble(),
                      activeColor: activeColor,
                      label: value.toString(),
                      onChanged: (next) {
                        setDialogState(() {
                          onChanged(next.round());
                          updateFromRgb();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      value.toString(),
                      textAlign: TextAlign.end,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
            }

            final selectedColor = _colorFromHex(selectedHex);
            return AlertDialog(
              title: Text('Choose brand color'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Icon(
                                Icons.storefront_outlined,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Store accent',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    selectedHex,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.78,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Quick colors',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final hex in _brandColorPresets)
                            _buildColorSwatch(
                              hex: hex,
                              selected: hex == selectedHex,
                              onSelected: (next) {
                                setDialogState(() => setSelectedHex(next));
                              },
                            ),
                        ],
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Fine tune',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 8),
                      channelSlider(
                        label: 'Red',
                        value: red,
                        activeColor: Colors.red,
                        onChanged: (next) => red = next,
                      ),
                      channelSlider(
                        label: 'Green',
                        value: green,
                        activeColor: Colors.green,
                        onChanged: (next) => green = next,
                      ),
                      channelSlider(
                        label: 'Blue',
                        value: blue,
                        activeColor: Colors.blue,
                        onChanged: (next) => blue = next,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(selectedHex),
                  icon: Icon(Icons.check_outlined),
                  label: Text('Use color'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _colorController.text = picked;
    });
  }

  Widget _buildColorSwatch({
    required String hex,
    required bool selected,
    required ValueChanged<String> onSelected,
  }) {
    final color = _colorFromHex(hex);
    return Tooltip(
      message: hex,
      child: InkWell(
        onTap: () => onSelected(hex),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outline,
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: selected ? Icon(Icons.check, color: Colors.white) : null,
        ),
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

  Widget _buildCoverGalleryField() {
    final coverUrls = _normalizedCoverUrls();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _addCoverUrl(_coverController.text),
                  icon: Icon(Icons.add_photo_alternate_outlined),
                  label: Text('Add URL'),
                ),
                OutlinedButton.icon(
                  onPressed: _uploadingCover
                      ? null
                      : () => _pickAndUploadImage('cover'),
                  icon: _uploadingCover
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.upload_file_outlined),
                  label: Text(
                    _uploadingCover ? 'Uploading...' : 'Upload photo',
                  ),
                ),
              ],
            );
            final input = TextField(
              controller: _coverController,
              decoration: InputDecoration(
                labelText: 'Add store photo URL',
                hintText: 'https://...',
                prefixIcon: Icon(Icons.photo_library_outlined),
                suffixIcon: _coverController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: Icon(Icons.close_outlined),
                        onPressed: () => setState(_coverController.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _addCoverUrl(_coverController.text),
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [input, SizedBox(height: 10), buttons],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: input),
                SizedBox(width: 10),
                buttons,
              ],
            );
          },
        ),
        SizedBox(height: 12),
        if (coverUrls.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.slideshow_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No store photos yet. Upload or add URLs to create a storefront slideshow.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < coverUrls.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == coverUrls.length - 1 ? 0 : 12,
                    ),
                    child: _buildCoverThumb(
                      coverUrls[index],
                      index,
                      coverUrls.length,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCoverThumb(String url, int index, int count) {
    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (imageContext, error, stackTrace) => Container(
                    color: Theme.of(
                      imageContext,
                    ).colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    index == 0 ? 'Main' : 'Slide ${index + 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Move left',
                  onPressed: index == 0 ? null : () => _moveCoverUrl(index, -1),
                  icon: Icon(Icons.chevron_left_outlined),
                ),
                IconButton(
                  tooltip: 'Move right',
                  onPressed: index >= count - 1
                      ? null
                      : () => _moveCoverUrl(index, 1),
                  icon: Icon(Icons.chevron_right_outlined),
                ),
                Spacer(),
                IconButton(
                  tooltip: 'Remove photo',
                  onPressed: () => _removeCoverUrl(url),
                  icon: Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addCoverUrl(String value, {bool showMessage = true}) {
    final clean = value.trim();
    if (clean.isEmpty) {
      if (showMessage) {
        _showError(
          Exception('Enter a photo URL first.'),
          'Enter a photo URL first.',
        );
      }
      return;
    }
    if (!_isRemoteUrl(clean)) {
      _showError(
        Exception('Use a valid http or https photo URL.'),
        'Use a valid http or https photo URL.',
      );
      return;
    }
    setState(() {
      final urls = _normalizedCoverUrls();
      if (!urls.contains(clean) && urls.length < 8) {
        urls.add(clean);
      }
      _coverUrls = urls;
      _coverController.clear();
    });
  }

  void _removeCoverUrl(String url) {
    setState(() {
      _coverUrls = _normalizedCoverUrls().where((item) => item != url).toList();
    });
  }

  void _moveCoverUrl(int index, int delta) {
    final nextIndex = index + delta;
    final urls = _normalizedCoverUrls();
    if (nextIndex < 0 || nextIndex >= urls.length) return;
    setState(() {
      final item = urls.removeAt(index);
      urls.insert(nextIndex, item);
      _coverUrls = urls;
    });
  }

  List<String> _normalizedCoverUrls() {
    final seen = <String>{};
    return _coverUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .take(8)
        .toList();
  }

  Widget _buildCard(List<Widget> children) {
    return StitchCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Color get _brandColor {
    return _colorFromHex(_colorController.text);
  }

  Color _colorFromHex(String hex) {
    final clean = _normalizeColorInput(hex);
    final value = int.tryParse(clean.substring(1), radix: 16);
    if (value == null) return Color(0xFFff2a6d);
    return Color(value + 0xFF000000);
  }

  int _hexChannel(String hex, int index) {
    final clean = _normalizeColorInput(hex);
    final start = 1 + (index * 2);
    return int.tryParse(clean.substring(start, start + 2), radix: 16) ?? 0;
  }

  String _hexFromRgb(int red, int green, int blue) {
    String channel(int value) =>
        value.clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${channel(red)}${channel(green)}${channel(blue)}';
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
