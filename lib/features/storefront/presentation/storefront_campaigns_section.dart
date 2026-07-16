import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/storefront_campaign_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../products/data/product_repository.dart';
import '../../services/data/service_repository.dart';

class StorefrontCampaignsSection extends StatefulWidget {
  final String storefrontType;

  const StorefrontCampaignsSection({super.key, this.storefrontType = 'retail'});

  @override
  State<StorefrontCampaignsSection> createState() =>
      _StorefrontCampaignsSectionState();
}

class _StorefrontCampaignsSectionState
    extends State<StorefrontCampaignsSection> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<StorefrontCampaign> _campaigns = const [];
  List<Map<String, dynamic>> _products = const [];

  String get _itemsLabel =>
      widget.storefrontType == 'services' ? 'services' : 'products';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        StorefrontCampaignService.list(storefrontType: widget.storefrontType),
        _loadCampaignItems(),
      ]);
      if (!mounted) return;
      setState(() {
        _campaigns = results[0] as List<StorefrontCampaign>;
        _products = (results[1] as List<Map<String, dynamic>>)
            .where(
              (product) =>
                  product['deleted_at'] == null &&
                  (product['show_online'] == null ||
                      product['show_online'] != 0),
            )
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadCampaignItems() async {
    if (widget.storefrontType != 'services') return ProductRepository.getAll();
    final services = await ServiceRepository.getServices(activeOnly: true);
    return services
        .map(
          (service) => <String, dynamic>{
            ...service,
            'id': 'service:${service['id']}',
            'brand': 'Service',
            'show_online': 1,
          },
        )
        .toList();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([StorefrontCampaign? campaign]) async {
    final draft = await showDialog<_CampaignDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CampaignEditorDialog(
        campaign: campaign,
        products: _products,
        storefrontType: widget.storefrontType,
      ),
    );
    if (draft == null) return;
    await _run(() async {
      if (campaign == null) {
        await StorefrontCampaignService.create(draft.toJson());
      } else {
        await StorefrontCampaignService.update(campaign.id, draft.toJson());
      }
    });
  }

  Future<void> _togglePublished(StorefrontCampaign campaign) async {
    await _run(() async {
      if (campaign.isPublished) {
        await StorefrontCampaignService.unpublish(campaign.id);
      } else {
        await StorefrontCampaignService.publish(campaign.id);
      }
    });
  }

  Future<void> _delete(StorefrontCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete campaign?'),
        content: Text(
          '“${campaign.name}” and its shareable page will be removed. Products are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => StorefrontCampaignService.delete(campaign.id));
    }
  }

  Future<void> _copy(StorefrontCampaign campaign) async {
    final url = campaign.url?.toString();
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Campaign link copied')));
  }

  Future<void> _open(StorefrontCampaign campaign) async {
    final url = campaign.url;
    if (url == null) return;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open the campaign website.');
    }
  }

  Future<void> _shareWhatsApp(StorefrontCampaign campaign) async {
    final url = campaign.url?.toString();
    if (url == null || url.isEmpty) return;
    final message = '${campaign.title}\n\n$url';
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open WhatsApp.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 680;
                      final introduction = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.campaign_outlined,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Campaign landing pages',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Build reusable pages for launches, collections, and WhatsApp promotions. Every published campaign gets its own customer URL.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final action = FilledButton.icon(
                        onPressed: _busy || _products.isEmpty
                            ? null
                            : () => _edit(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New campaign'),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            introduction,
                            const SizedBox(height: 18),
                            action,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: introduction),
                          const SizedBox(width: 24),
                          action,
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorNotice(message: _error!, onRetry: _load),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_products.isEmpty)
                _EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Publish $_itemsLabel first',
                  message:
                      'Campaign pages use your online $_itemsLabel. Publish at least one, then return here.',
                )
              else if (_campaigns.isEmpty)
                _EmptyState(
                  icon: Icons.web_asset_outlined,
                  title: 'Create your first campaign page',
                  message:
                      'Choose products, add a clear headline, preview the page, and share one focused URL with customers.',
                  action: FilledButton.icon(
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create campaign'),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 800
                        ? (constraints.maxWidth - 14) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: _campaigns
                          .map(
                            (campaign) => SizedBox(
                              width: width,
                              child: _campaignCard(campaign),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campaignCard(StorefrontCampaign campaign) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 124,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              image: campaign.heroImageUrl == null
                  ? null
                  : DecorationImage(
                      image: NetworkImage(campaign.heroImageUrl!),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.24),
                        BlendMode.darken,
                      ),
                    ),
            ),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: Chip(
                avatar: Icon(
                  campaign.isPublished
                      ? Icons.public_rounded
                      : Icons.edit_note_rounded,
                  size: 16,
                ),
                label: Text(campaign.isPublished ? 'Live' : 'Draft'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  campaign.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  campaign.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('${campaign.productIds.length} selected $_itemsLabel'),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _edit(campaign),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                    if (campaign.isPublished) ...[
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _open(campaign),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Open'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _copy(campaign),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Copy link'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _shareWhatsApp(campaign),
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                    ],
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _togglePublished(campaign),
                      icon: Icon(
                        campaign.isPublished
                            ? Icons.visibility_off_outlined
                            : Icons.publish_rounded,
                        size: 18,
                      ),
                      label: Text(
                        campaign.isPublished ? 'Unpublish' : 'Publish',
                      ),
                    ),
                    if (!campaign.isPublished)
                      IconButton(
                        tooltip: 'Delete campaign',
                        onPressed: _busy ? null : () => _delete(campaign),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _message(Object error) => AppErrorMessage.from(
    error,
    fallback: 'The campaign action could not be completed. Try again.',
  );
}

class _CampaignEditorDialog extends StatefulWidget {
  final StorefrontCampaign? campaign;
  final List<Map<String, dynamic>> products;
  final String storefrontType;

  const _CampaignEditorDialog({
    required this.campaign,
    required this.products,
    required this.storefrontType,
  });

  @override
  State<_CampaignEditorDialog> createState() => _CampaignEditorDialogState();
}

class _CampaignEditorDialogState extends State<_CampaignEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _eyebrow;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _badge;
  late final TextEditingController _button;
  late final TextEditingController _image;
  late final TextEditingController _highlights;
  late Set<String> _selectedProducts;
  String _search = '';
  String? _validation;

  @override
  void initState() {
    super.initState();
    final campaign = widget.campaign;
    _name = TextEditingController(text: campaign?.name ?? '');
    _slug = TextEditingController(text: campaign?.slug ?? '');
    _eyebrow = TextEditingController(
      text: campaign?.eyebrow ?? 'Featured collection',
    );
    _title = TextEditingController(text: campaign?.title ?? '');
    _description = TextEditingController(text: campaign?.description ?? '');
    _badge = TextEditingController(text: campaign?.badgeLabel ?? '');
    _button = TextEditingController(
      text: campaign?.buttonLabel ?? 'Shop the campaign',
    );
    _image = TextEditingController(text: campaign?.heroImageUrl ?? '');
    _highlights = TextEditingController(
      text: campaign?.highlights.join('\n') ?? '',
    );
    _selectedProducts = {...?campaign?.productIds};
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _eyebrow.dispose();
    _title.dispose();
    _description.dispose();
    _badge.dispose();
    _button.dispose();
    _image.dispose();
    _highlights.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsLabel = widget.storefrontType == 'services'
        ? 'services'
        : 'products';
    final filteredProducts = widget.products.where((product) {
      final query = _search.trim().toLowerCase();
      return query.isEmpty ||
          product['name']?.toString().toLowerCase().contains(query) == true ||
          product['brand']?.toString().toLowerCase().contains(query) == true;
    }).toList();
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 720;
    final dialogWidth = (screen.width - 64).clamp(280.0, 820.0);
    final dialogHeight = (screen.height - 170).clamp(420.0, 650.0);
    final details = _campaignDetailsPane(compact: compact);
    final products = _productPickerPane(
      itemsLabel: itemsLabel,
      filteredProducts: filteredProducts,
      compact: compact,
    );
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: compact ? 16 : 24,
      ),
      title: Text(
        widget.campaign == null ? 'Create campaign page' : 'Edit campaign page',
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_validation != null) ...[
              Text(
                _validation!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 10),
            ],
            if (compact)
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          tabs: [
                            const Tab(text: 'Page details'),
                            Tab(
                              text: '${_selectedProducts.length} $itemsLabel',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(children: [details, products]),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: details),
                    const VerticalDivider(width: 33),
                    Expanded(child: products),
                  ],
                ),
              ),
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save draft'),
        ),
      ],
    );
  }

  Widget _campaignDetailsPane({required bool compact}) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(right: compact ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Internal campaign name',
            ),
            onChanged: (value) {
              if (_slug.text.trim().isEmpty) _slug.text = _slugify(value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _slug,
            decoration: const InputDecoration(
              labelText: 'Share URL ending',
              prefixText: '/campaign/',
              helperText: 'Lowercase words and hyphens only.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _eyebrow,
            decoration: const InputDecoration(labelText: 'Small label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Customer headline'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Campaign description',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                Expanded(
                  child: TextField(
                    controller: _badge,
                    decoration: const InputDecoration(
                      labelText: 'Optional badge',
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _button,
                    decoration: const InputDecoration(
                      labelText: 'Button label',
                    ),
                  ),
                ),
              ];
              if (constraints.maxWidth < 440) {
                return Column(
                  children: [
                    TextField(
                      controller: _badge,
                      decoration: const InputDecoration(
                        labelText: 'Optional badge',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _button,
                      decoration: const InputDecoration(
                        labelText: 'Button label',
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  fields.first,
                  const SizedBox(width: 12),
                  fields.last,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _highlights,
            minLines: 3,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Highlights',
              helperText: 'One truthful benefit per line, up to four.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _image,
            decoration: const InputDecoration(
              labelText: 'Optional hero image URL',
              helperText:
                  'Use a secure https image. Leave blank for a text-led page.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _productPickerPane({
    required String itemsLabel,
    required List<Map<String, dynamic>> filteredProducts,
    required bool compact,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: compact ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Campaign $itemsLabel',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '${_selectedProducts.length}/24 selected',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search $itemsLabel',
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                final id = product['id']?.toString() ?? '';
                final selected = _selectedProducts.contains(id);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  title: Text(
                    product['name']?.toString() ?? 'Product',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: product['brand'] == null
                      ? null
                      : Text(product['brand'].toString()),
                  onChanged: (value) {
                    setState(() {
                      if (value == true && _selectedProducts.length < 24) {
                        _selectedProducts.add(id);
                      } else if (value != true) {
                        _selectedProducts.remove(id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (_name.text.trim().isEmpty || _title.text.trim().isEmpty) {
      setState(
        () => _validation = 'Add an internal name and customer headline.',
      );
      return;
    }
    if (_selectedProducts.isEmpty) {
      setState(
        () => _validation =
            'Select at least one ${widget.storefrontType == 'services' ? 'service' : 'product'} for this campaign.',
      );
      return;
    }
    Navigator.pop(
      context,
      _CampaignDraft(
        name: _name.text.trim(),
        slug: _slugify(_slug.text),
        eyebrow: _eyebrow.text.trim(),
        title: _title.text.trim(),
        description: _description.text.trim(),
        badgeLabel: _badge.text.trim(),
        buttonLabel: _button.text.trim(),
        heroImageUrl: _image.text.trim(),
        highlights: _highlights.text
            .split(RegExp(r'[\r\n]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .take(4)
            .toList(),
        productIds: _selectedProducts.toList(),
        storefrontType: widget.storefrontType,
      ),
    );
  }

  String _slugify(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _CampaignDraft {
  final String name;
  final String slug;
  final String eyebrow;
  final String title;
  final String description;
  final String badgeLabel;
  final String buttonLabel;
  final String heroImageUrl;
  final List<String> highlights;
  final List<String> productIds;
  final String storefrontType;

  const _CampaignDraft({
    required this.name,
    required this.slug,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.badgeLabel,
    required this.buttonLabel,
    required this.heroImageUrl,
    required this.highlights,
    required this.productIds,
    required this.storefrontType,
  });

  Map<String, dynamic> toJson() => {
    'branchId': 'main_branch',
    'storefrontType': storefrontType,
    'name': name,
    'slug': slug,
    'eyebrow': eyebrow,
    'title': title,
    'description': description,
    'badgeLabel': badgeLabel,
    'buttonLabel': buttonLabel,
    if (heroImageUrl.isNotEmpty) 'heroImageUrl': heroImageUrl,
    'highlights': highlights,
    'productIds': productIds,
  };
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            Icon(icon, size: 44, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
