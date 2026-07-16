import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

class StorefrontComponentSelection {
  final String component;
  final String? binding;
  final String selector;
  final String? parentSelector;
  final String label;
  final String? text;

  const StorefrontComponentSelection({
    required this.component,
    required this.binding,
    required this.selector,
    required this.parentSelector,
    required this.label,
    required this.text,
  });

  factory StorefrontComponentSelection.fromJson(Map<String, dynamic> json) {
    String? optional(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return StorefrontComponentSelection(
      component: optional('component') ?? 'section',
      binding: optional('binding'),
      selector: optional('selector') ?? '',
      parentSelector: optional('parentSelector'),
      label: optional('label') ?? optional('component') ?? 'Selected section',
      text: optional('text'),
    );
  }

  Map<String, dynamic> toJson() => {
    'component': component,
    if (binding != null) 'binding': binding,
    'selector': selector,
    if (parentSelector != null) 'parentSelector': parentSelector,
    'label': label,
    if (text != null) 'text': text,
  };
}

class StorefrontPreviewEditRequest {
  final String instruction;
  final StorefrontComponentSelection selection;

  const StorefrontPreviewEditRequest({
    required this.instruction,
    required this.selection,
  });
}

enum _PreviewViewport { desktop, tablet, mobile }

class StorefrontInAppPreviewDialog extends StatefulWidget {
  final Uri previewUri;
  final int buildVersion;
  final String buildName;

  const StorefrontInAppPreviewDialog({
    super.key,
    required this.previewUri,
    required this.buildVersion,
    required this.buildName,
  });

  @override
  State<StorefrontInAppPreviewDialog> createState() =>
      _StorefrontInAppPreviewDialogState();
}

class _StorefrontInAppPreviewDialogState
    extends State<StorefrontInAppPreviewDialog> {
  final WebviewController _controller = WebviewController();
  final TextEditingController _instruction = TextEditingController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StorefrontComponentSelection? _selection;
  _PreviewViewport _viewport = _PreviewViewport.desktop;
  bool _initializing = true;
  bool _loading = true;
  String? _error;

  Uri get _inspectUri => widget.previewUri.replace(
    queryParameters: {...widget.previewUri.queryParameters, 'pikiInspect': '1'},
  );

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _subscriptions.add(_controller.webMessage.listen(_handleWebMessage));
      _subscriptions.add(
        _controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() => _loading = state == LoadingState.loading);
        }),
      );
      await _controller.loadUrl(_inspectUri.toString());
    } on PlatformException catch (error) {
      _error = error.message ?? 'The Windows browser preview could not start.';
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _handleWebMessage(dynamic message) {
    dynamic decoded = message;
    if (message is String) {
      try {
        decoded = jsonDecode(message);
      } catch (_) {
        return;
      }
    }
    if (decoded is! Map) return;
    final data = Map<String, dynamic>.from(decoded);
    if (data['channel'] != 'piki-storefront-studio' ||
        data['type'] != 'section-selected' ||
        data['selection'] is! Map) {
      return;
    }
    final selected = StorefrontComponentSelection.fromJson(
      Map<String, dynamic>.from(data['selection'] as Map),
    );
    if (!mounted) return;
    setState(() => _selection = selected);
  }

  double? _viewportWidth(double availableWidth) {
    return switch (_viewport) {
      _PreviewViewport.desktop => null,
      _PreviewViewport.tablet => availableWidth.clamp(0, 768).toDouble(),
      _PreviewViewport.mobile => availableWidth.clamp(0, 390).toDouble(),
    };
  }

  void _submit() {
    final selection = _selection;
    final instruction = _instruction.text.trim();
    if (selection == null || instruction.length < 4) return;
    Navigator.pop(
      context,
      StorefrontPreviewEditRequest(
        instruction: instruction,
        selection: selection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
          titleSpacing: 4,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exact storefront preview · v${widget.buildVersion}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                widget.buildName,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            SegmentedButton<_PreviewViewport>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _PreviewViewport.desktop,
                  icon: Icon(Icons.desktop_windows_outlined, size: 18),
                  tooltip: 'Desktop',
                ),
                ButtonSegment(
                  value: _PreviewViewport.tablet,
                  icon: Icon(Icons.tablet_outlined, size: 18),
                  tooltip: 'Tablet',
                ),
                ButtonSegment(
                  value: _PreviewViewport.mobile,
                  icon: Icon(Icons.phone_iphone_rounded, size: 18),
                  tooltip: 'Mobile',
                ),
              ],
              selected: {_viewport},
              onSelectionChanged: (value) {
                setState(() => _viewport = value.first);
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Reload exact preview',
              onPressed: _controller.value.isInitialized
                  ? () => _controller.reload()
                  : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Open in your browser',
              onPressed: () => launchUrl(
                widget.previewUri,
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
            const SizedBox(width: 12),
          ],
          bottom: _loading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
        ),
        body: Row(
          children: [
            Expanded(
              child: ColoredBox(
                color: colors.surfaceContainerHighest,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewWidth = _viewportWidth(constraints.maxWidth);
                    return Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: previewWidth,
                        height: constraints.maxHeight,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            if (_viewport != _PreviewViewport.desktop)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 28,
                              ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _previewBody(colors),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              width: size.width >= 1280 ? 390 : 340,
              child: _pikiPanel(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewBody(ColorScheme colors) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || !_controller.value.isInitialized) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.web_asset_off_outlined,
                  size: 52,
                  color: colors.error,
                ),
                const SizedBox(height: 16),
                const Text(
                  'In-app preview is unavailable',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Microsoft Edge WebView2 is not available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    widget.previewUri,
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open exact preview'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Webview(
      _controller,
      permissionRequested: (_, _, _) => WebviewPermissionDecision.deny,
    );
  }

  Widget _pikiPanel(ColorScheme colors) {
    final selected = _selection;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Point & edit with Piki',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Click a section in the website',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: selected == null
                    ? Container(
                        key: const ValueKey('empty'),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.ads_click_rounded, size: 30),
                            SizedBox(height: 10),
                            Text(
                              'Select the exact component you want Piki to change.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        key: ValueKey(selected.selector),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 7),
                                const Text(
                                  'Selected component',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              selected.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              selected.binding == null
                                  ? selected.component
                                  : 'Live ${selected.binding} binding',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _instruction,
                enabled: selected != null,
                minLines: 5,
                maxLines: 9,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Tell Piki what to change',
                  alignLabelWithHint: true,
                  hintText:
                      'Example: Move this section above the hero, use a two-column layout, and make its heading more elegant on mobile.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Piki receives the selected component path and the current site code. Unrelated sections are preserved.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed:
                    selected != null && _instruction.text.trim().length >= 4
                    ? _submit
                    : null,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('Edit selected section'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _instruction.dispose();
    _controller.dispose();
    super.dispose();
  }
}
