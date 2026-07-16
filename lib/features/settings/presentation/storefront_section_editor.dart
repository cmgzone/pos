import 'package:flutter/material.dart';

import '../../../core/services/storefront_theme_service.dart';

Future<List<Map<String, dynamic>>?> showStorefrontSectionEditor(
  BuildContext context,
  StorefrontTheme theme,
) {
  return showStorefrontSectionsEditor(
    context,
    sections: theme.sections,
    requireCatalog: true,
  );
}

Future<List<Map<String, dynamic>>?> showStorefrontSectionsEditor(
  BuildContext context, {
  required List<StorefrontThemeSection> sections,
  bool requireCatalog = false,
}) {
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StorefrontSectionEditorDialog(
      sections: sections,
      requireCatalog: requireCatalog,
    ),
  );
}

class _StorefrontSectionEditorDialog extends StatefulWidget {
  final List<StorefrontThemeSection> sections;
  final bool requireCatalog;

  const _StorefrontSectionEditorDialog({
    required this.sections,
    required this.requireCatalog,
  });

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
    _sections = [...widget.sections];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 620;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: compact ? 16 : 24,
      ),
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
        width: (screen.width - 72).clamp(260.0, 760.0),
        height: (screen.height - 170).clamp(360.0, 610.0),
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
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 470;
            final identity = Row(
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
              ],
            );
            final controls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: section.enabled,
                  onChanged: section.type == 'catalog' && widget.requireCatalog
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
                  tooltip: section.type == 'catalog' && widget.requireCatalog
                      ? 'The full catalogue is required'
                      : 'Remove section',
                  onPressed: section.type == 'catalog' && widget.requireCatalog
                      ? null
                      : () => setState(() => _sections.removeAt(index)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  Align(alignment: Alignment.centerRight, child: controls),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                controls,
              ],
            );
          },
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
      if (type == 'richText') 'content': 'Add your page content here.',
      if (type == 'faq')
        'items': const [
          {
            'question': 'How can we help?',
            'answer': 'Replace this with a clear answer for your customers.',
          },
        ],
      if (type == 'gallery') 'items': const [],
      if (type == 'video') ...{'videoUrl': '', 'caption': ''},
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
    final content = TextEditingController(
      text: current.type == 'faq'
          ? (data['items'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (item) =>
                      '${item['question']?.toString() ?? ''} | ${item['answer']?.toString() ?? ''}',
                )
                .join('\n')
          : current.type == 'gallery'
          ? (data['items'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (item) =>
                      '${item['imageUrl']?.toString() ?? ''} | ${item['caption']?.toString() ?? ''}',
                )
                .join('\n')
          : data['content']?.toString() ?? data['videoUrl']?.toString() ?? '',
    );
    final button = TextEditingController(
      text: data['buttonLabel']?.toString() ?? '',
    );
    final icon = TextEditingController(text: data['icon']?.toString() ?? '');
    var style = data['style']?.toString() ?? 'default';
    var width = data['width']?.toString() ?? 'contained';
    var spacing = data['spacing']?.toString() ?? 'comfortable';
    var columns = int.tryParse(data['columns']?.toString() ?? '') ?? 3;
    var imagePosition = data['imagePosition']?.toString() ?? 'right';
    var alignment = data['alignment']?.toString() ?? 'left';
    var action = data['buttonAction']?.toString() ?? 'none';
    var showImage = data['showImage'] != false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Text(
            'Edit ${_sectionDetails(current.type).label.toLowerCase()}',
          ),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 520.0),
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
                    const SizedBox(height: 10),
                    TextField(
                      controller: icon,
                      decoration: const InputDecoration(
                        labelText: 'Icon name (optional)',
                        hintText: 'ShoppingBag, Sparkles, Heart, Truck',
                        helperText:
                            'Use any Lucide icon name. Piki can choose this automatically.',
                      ),
                    ),
                  ],
                  if (const {
                    'richText',
                    'faq',
                    'gallery',
                    'video',
                  }.contains(current.type)) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: content,
                      minLines: 4,
                      maxLines: 10,
                      decoration: InputDecoration(
                        labelText: current.type == 'faq'
                            ? 'Questions and answers'
                            : current.type == 'gallery'
                            ? 'Image URLs and captions'
                            : current.type == 'video'
                            ? 'YouTube or Vimeo URL'
                            : 'Page content',
                        helperText: current.type == 'faq'
                            ? 'One per line: Question | Answer'
                            : current.type == 'gallery'
                            ? 'One per line: HTTPS image URL | Caption'
                            : null,
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: width,
                          decoration: const InputDecoration(
                            labelText: 'Content width',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'narrow',
                              child: Text('Narrow'),
                            ),
                            DropdownMenuItem(
                              value: 'contained',
                              child: Text('Contained'),
                            ),
                            DropdownMenuItem(
                              value: 'wide',
                              child: Text('Wide'),
                            ),
                            DropdownMenuItem(
                              value: 'full',
                              child: Text('Full width'),
                            ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => width = value ?? width),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: spacing,
                          decoration: const InputDecoration(
                            labelText: 'Vertical spacing',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'none',
                              child: Text('None'),
                            ),
                            DropdownMenuItem(
                              value: 'compact',
                              child: Text('Compact'),
                            ),
                            DropdownMenuItem(
                              value: 'comfortable',
                              child: Text('Comfortable'),
                            ),
                            DropdownMenuItem(
                              value: 'spacious',
                              child: Text('Spacious'),
                            ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => spacing = value ?? spacing),
                        ),
                      ),
                    ],
                  ),
                  if (const {'benefits', 'gallery'}.contains(current.type)) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: columns,
                      decoration: const InputDecoration(labelText: 'Columns'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 column')),
                        DropdownMenuItem(value: 2, child: Text('2 columns')),
                        DropdownMenuItem(value: 3, child: Text('3 columns')),
                        DropdownMenuItem(value: 4, child: Text('4 columns')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => columns = value ?? columns),
                    ),
                  ],
                  if (const {
                    'hero',
                    'story',
                    'gallery',
                  }.contains(current.type)) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: imagePosition,
                      decoration: const InputDecoration(
                        labelText: 'Image position',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'left', child: Text('Left')),
                        DropdownMenuItem(value: 'right', child: Text('Right')),
                        DropdownMenuItem(
                          value: 'top',
                          child: Text('Above content'),
                        ),
                        DropdownMenuItem(
                          value: 'background',
                          child: Text('Background'),
                        ),
                      ],
                      onChanged: (value) => setDialogState(
                        () => imagePosition = value ?? imagePosition,
                      ),
                    ),
                  ],
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
                      isExpanded: true,
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
                      expandedInsets: EdgeInsets.zero,
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
      data['width'] = width;
      data['spacing'] = spacing;
      data['columns'] = columns;
      data['imagePosition'] = imagePosition;
      if (isAnnouncement) {
        data['text'] = title.text.trim();
      } else {
        data['title'] = title.text.trim();
        data['eyebrow'] = eyebrow.text.trim();
        data['body'] = body.text.trim();
        data['icon'] = icon.text.trim();
      }
      if (_supportsAction(current.type)) {
        data['buttonLabel'] = button.text.trim();
        data['buttonAction'] = action;
      }
      if (_supportsAlignment(current.type)) data['alignment'] = alignment;
      if (current.type == 'hero' || current.type == 'story') {
        data['showImage'] = showImage;
      }
      if (current.type == 'richText') data['content'] = content.text.trim();
      if (current.type == 'video') data['videoUrl'] = content.text.trim();
      if (current.type == 'faq') {
        data['items'] = content.text
            .split('\n')
            .map((line) => line.split('|'))
            .where((parts) => parts.length >= 2)
            .map(
              (parts) => {
                'question': parts.first.trim(),
                'answer': parts.skip(1).join('|').trim(),
              },
            )
            .toList();
      }
      if (current.type == 'gallery') {
        data['items'] = content.text
            .split('\n')
            .map((line) => line.split('|'))
            .where((parts) => parts.first.trim().isNotEmpty)
            .map(
              (parts) => {
                'imageUrl': parts.first.trim(),
                'caption': parts.skip(1).join('|').trim(),
              },
            )
            .toList();
      }
      setState(() {
        _sections[index] = StorefrontThemeSection.fromJson(data);
      });
    }
    title.dispose();
    eyebrow.dispose();
    body.dispose();
    content.dispose();
    button.dispose();
    icon.dispose();
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
    key: 'richText',
    label: 'Rich text',
    defaultTitle: 'Page content',
    icon: Icons.notes_rounded,
  ),
  _SectionTypeDetails(
    key: 'faq',
    label: 'Frequently asked questions',
    defaultTitle: 'Common questions',
    icon: Icons.help_outline_rounded,
  ),
  _SectionTypeDetails(
    key: 'gallery',
    label: 'Image gallery',
    defaultTitle: 'Gallery',
    icon: Icons.photo_library_outlined,
  ),
  _SectionTypeDetails(
    key: 'video',
    label: 'Video',
    defaultTitle: 'Watch the story',
    icon: Icons.play_circle_outline_rounded,
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
