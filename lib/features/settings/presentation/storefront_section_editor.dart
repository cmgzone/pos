import 'package:flutter/material.dart';

import '../../../core/services/storefront_theme_service.dart';

Future<List<Map<String, dynamic>>?> showStorefrontSectionEditor(
  BuildContext context,
  StorefrontTheme theme,
) {
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StorefrontSectionEditorDialog(theme: theme),
  );
}

class _StorefrontSectionEditorDialog extends StatefulWidget {
  final StorefrontTheme theme;

  const _StorefrontSectionEditorDialog({required this.theme});

  @override
  State<_StorefrontSectionEditorDialog> createState() =>
      _StorefrontSectionEditorDialogState();
}

class _StorefrontSectionEditorDialogState
    extends State<_StorefrontSectionEditorDialog> {
  late List<StorefrontThemeSection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = [...widget.theme.sections];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 18, 0),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.view_quilt_outlined, color: colors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Edit website sections')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 610,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Drag sections into the customer journey you want. Changes stay in this draft until you publish.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.all(10),
                  buildDefaultDragHandles: false,
                  itemCount: _sections.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) => _sectionTile(index),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                PopupMenuButton<String>(
                  enabled: _sections.length < 12,
                  onSelected: _addSection,
                  itemBuilder: (context) => _sectionTypes
                      .where(
                        (entry) =>
                            entry.key != 'catalog' ||
                            !_sections.any(
                              (section) => section.type == 'catalog',
                            ),
                      )
                      .map(
                        (entry) => PopupMenuItem<String>(
                          value: entry.key,
                          child: Row(
                            children: [
                              Icon(entry.icon, size: 19),
                              const SizedBox(width: 10),
                              Text(entry.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      _sections.length >= 12
                          ? 'Section limit reached'
                          : 'Add section',
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_sections.where((section) => section.enabled).length} visible · ${_sections.length}/12 sections',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _sections.map((section) => section.toJson()).toList(),
          ),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save draft layout'),
        ),
      ],
    );
  }

  Widget _sectionTile(int index) {
    final section = _sections[index];
    final details = _sectionDetails(section.type);
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey(section.id),
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: section.enabled
          ? colors.surface
          : colors.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(details.icon, size: 19, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title.trim().isEmpty
                        ? details.label
                        : section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: section.enabled,
              onChanged: section.type == 'catalog'
                  ? null
                  : (value) => setState(() {
                      _sections[index] = section.copyWith(enabled: value);
                    }),
            ),
            IconButton(
              tooltip: 'Edit copy and style',
              onPressed: () => _editSection(index),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: section.type == 'catalog'
                  ? 'The full catalogue is required'
                  : 'Remove section',
              onPressed: section.type == 'catalog'
                  ? null
                  : () => setState(() => _sections.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final section = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, section);
    });
  }

  void _addSection(String type) {
    final details = _sectionDetails(type);
    final id = '$type-${DateTime.now().microsecondsSinceEpoch}';
    final data = <String, dynamic>{
      'id': id,
      'type': type,
      'enabled': true,
      'style': type == 'promoBanner' ? 'accent' : 'default',
      if (type == 'announcement')
        'text': details.defaultTitle
      else
        'title': details.defaultTitle,
      if (type != 'announcement') 'eyebrow': '',
      if (type != 'announcement') 'body': '',
      if (type == 'featuredProducts') ...{'source': 'featured', 'limit': 4},
      if (type == 'benefits')
        'items': const [
          {
            'title': 'Easy ordering',
            'body': 'Browse and order in a few simple steps.',
            'icon': 'sparkles',
          },
          {
            'title': 'Helpful support',
            'body': 'Contact the team when you need help choosing.',
            'icon': 'message',
          },
          {
            'title': 'Order updates',
            'body': 'Follow the order after checkout.',
            'icon': 'truck',
          },
        ],
      if (type == 'hero') ...{
        'buttonLabel': 'Shop now',
        'buttonAction': 'catalog',
        'alignment': 'left',
        'showImage': true,
      },
      if (type == 'promoBanner' || type == 'contact') ...{
        'buttonLabel': type == 'contact' ? 'Chat on WhatsApp' : 'Shop now',
        'buttonAction': type == 'contact' ? 'whatsapp' : 'catalog',
        'alignment': type == 'contact' ? 'center' : 'left',
      },
    };
    setState(() {
      _sections.add(StorefrontThemeSection.fromJson(data));
    });
  }

  Future<void> _editSection(int index) async {
    final current = _sections[index];
    final data = Map<String, dynamic>.from(current.data);
    final isAnnouncement = current.type == 'announcement';
    final title = TextEditingController(
      text: isAnnouncement
          ? data['text']?.toString()
          : data['title']?.toString(),
    );
    final eyebrow = TextEditingController(
      text: data['eyebrow']?.toString() ?? '',
    );
    final body = TextEditingController(text: data['body']?.toString() ?? '');
    final button = TextEditingController(
      text: data['buttonLabel']?.toString() ?? '',
    );
    var style = data['style']?.toString() ?? 'default';
    var alignment = data['alignment']?.toString() ?? 'left';
    var action = data['buttonAction']?.toString() ?? 'none';
    var showImage = data['showImage'] != false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Edit ${_sectionDetails(current.type).label.toLowerCase()}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: title,
                    maxLength: isAnnouncement ? 140 : 100,
                    decoration: InputDecoration(
                      labelText: isAnnouncement
                          ? 'Announcement text'
                          : 'Heading',
                    ),
                  ),
                  if (!isAnnouncement) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: eyebrow,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: 'Small label',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: body,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 360,
                      decoration: const InputDecoration(
                        labelText: 'Supporting copy',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: style,
                    decoration: const InputDecoration(
                      labelText: 'Section style',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'default',
                        child: Text('Default'),
                      ),
                      DropdownMenuItem(
                        value: 'surface',
                        child: Text('Soft surface'),
                      ),
                      DropdownMenuItem(
                        value: 'accent',
                        child: Text('Brand accent'),
                      ),
                      DropdownMenuItem(
                        value: 'contrast',
                        child: Text('High contrast'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => style = value ?? style),
                  ),
                  if (_supportsAction(current.type)) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: button,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Button label',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: action,
                      decoration: const InputDecoration(
                        labelText: 'Button action',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('No action'),
                        ),
                        DropdownMenuItem(
                          value: 'catalog',
                          child: Text('Open catalogue'),
                        ),
                        DropdownMenuItem(
                          value: 'whatsapp',
                          child: Text('Open WhatsApp'),
                        ),
                        DropdownMenuItem(
                          value: 'trackOrder',
                          child: Text('Track an order'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => action = value ?? action),
                    ),
                  ],
                  if (_supportsAlignment(current.type)) ...[
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'left', label: Text('Left')),
                        ButtonSegment(value: 'center', label: Text('Centre')),
                        ButtonSegment(value: 'right', label: Text('Right')),
                      ],
                      selected: {alignment},
                      onSelectionChanged: (value) =>
                          setDialogState(() => alignment = value.first),
                    ),
                  ],
                  if (current.type == 'hero' || current.type == 'story')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: showImage,
                      title: const Text('Show brand image'),
                      onChanged: (value) =>
                          setDialogState(() => showImage = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      data['style'] = style;
      if (isAnnouncement) {
        data['text'] = title.text.trim();
      } else {
        data['title'] = title.text.trim();
        data['eyebrow'] = eyebrow.text.trim();
        data['body'] = body.text.trim();
      }
      if (_supportsAction(current.type)) {
        data['buttonLabel'] = button.text.trim();
        data['buttonAction'] = action;
      }
      if (_supportsAlignment(current.type)) data['alignment'] = alignment;
      if (current.type == 'hero' || current.type == 'story') {
        data['showImage'] = showImage;
      }
      setState(() {
        _sections[index] = StorefrontThemeSection.fromJson(data);
      });
    }
    title.dispose();
    eyebrow.dispose();
    body.dispose();
    button.dispose();
  }

  bool _supportsAction(String type) =>
      const {'announcement', 'hero', 'promoBanner', 'contact'}.contains(type);

  bool _supportsAlignment(String type) =>
      const {'hero', 'promoBanner', 'story', 'contact'}.contains(type);
}

class _SectionTypeDetails {
  final String key;
  final String label;
  final String defaultTitle;
  final IconData icon;

  const _SectionTypeDetails({
    required this.key,
    required this.label,
    required this.defaultTitle,
    required this.icon,
  });
}

const _sectionTypes = <_SectionTypeDetails>[
  _SectionTypeDetails(
    key: 'announcement',
    label: 'Announcement bar',
    defaultTitle: 'A short store announcement',
    icon: Icons.campaign_outlined,
  ),
  _SectionTypeDetails(
    key: 'hero',
    label: 'Hero',
    defaultTitle: 'A clear reason to shop',
    icon: Icons.web_asset_outlined,
  ),
  _SectionTypeDetails(
    key: 'categoryShowcase',
    label: 'Category showcase',
    defaultTitle: 'Shop by category',
    icon: Icons.grid_view_outlined,
  ),
  _SectionTypeDetails(
    key: 'featuredProducts',
    label: 'Featured products',
    defaultTitle: 'Featured picks',
    icon: Icons.star_outline_rounded,
  ),
  _SectionTypeDetails(
    key: 'promoBanner',
    label: 'Promotion banner',
    defaultTitle: 'Something special for you',
    icon: Icons.local_offer_outlined,
  ),
  _SectionTypeDetails(
    key: 'benefits',
    label: 'Store benefits',
    defaultTitle: 'Why customers choose us',
    icon: Icons.verified_outlined,
  ),
  _SectionTypeDetails(
    key: 'story',
    label: 'Brand story',
    defaultTitle: 'Our story',
    icon: Icons.auto_stories_outlined,
  ),
  _SectionTypeDetails(
    key: 'catalog',
    label: 'Full catalogue',
    defaultTitle: 'Browse the store',
    icon: Icons.storefront_outlined,
  ),
  _SectionTypeDetails(
    key: 'contact',
    label: 'Contact callout',
    defaultTitle: 'Talk to the team',
    icon: Icons.chat_bubble_outline_rounded,
  ),
];

_SectionTypeDetails _sectionDetails(String type) {
  return _sectionTypes.firstWhere(
    (item) => item.key == type,
    orElse: () => _sectionTypes.last,
  );
}
