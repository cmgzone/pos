import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../core/services/piki_ai_job_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/piki_activity_panel.dart';

class StorefrontComponentSelection {
  final String component;
  final String? binding;
  final String selector;
  final String? parentSelector;
  final String label;
  final String? text;
  final String? element;
  final String? role;
  final String? scope;
  final String? hierarchy;
  final String? classes;
  final String? attributes;
  final String? dimensions;
  final String? styles;
  final String? siteBuildId;
  final String? siteMode;
  final String? selectedProductId;

  const StorefrontComponentSelection({
    required this.component,
    required this.binding,
    required this.selector,
    required this.parentSelector,
    required this.label,
    required this.text,
    this.element,
    this.role,
    this.scope,
    this.hierarchy,
    this.classes,
    this.attributes,
    this.dimensions,
    this.styles,
    this.siteBuildId,
    this.siteMode,
    this.selectedProductId,
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
      label: optional('label') ?? optional('component') ?? 'Selected element',
      text: optional('text'),
      element: optional('element'),
      role: optional('role'),
      scope: optional('scope'),
      hierarchy: optional('hierarchy'),
      classes: optional('classes'),
      attributes: optional('attributes'),
      dimensions: optional('dimensions'),
      styles: optional('styles'),
      siteBuildId: optional('siteBuildId'),
      siteMode: optional('siteMode'),
      selectedProductId: optional('selectedProductId'),
    );
  }

  Map<String, dynamic> toJson() => {
    'component': component,
    if (binding != null) 'binding': binding,
    'selector': selector,
    if (parentSelector != null) 'parentSelector': parentSelector,
    'label': label,
    if (text != null) 'text': text,
    if (element != null) 'element': element,
    if (role != null) 'role': role,
    if (scope != null) 'scope': scope,
    if (hierarchy != null) 'hierarchy': hierarchy,
    if (classes != null) 'classes': classes,
    if (attributes != null) 'attributes': attributes,
    if (dimensions != null) 'dimensions': dimensions,
    if (styles != null) 'styles': styles,
    if (siteBuildId != null) 'siteBuildId': siteBuildId,
    if (siteMode != null) 'siteMode': siteMode,
    if (selectedProductId != null) 'selectedProductId': selectedProductId,
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

class StorefrontPreviewJobCompletion {
  final Uri previewUri;
  final int? buildVersion;
  final String buildName;

  const StorefrontPreviewJobCompletion({
    required this.previewUri,
    required this.buildName,
    this.buildVersion,
  });
}

typedef StorefrontPreviewEditStarter =
    Future<PikiAiJob> Function(StorefrontPreviewEditRequest request);

typedef StorefrontPreviewJobCompletionResolver =
    Future<StorefrontPreviewJobCompletion?> Function(PikiAiJob job);

enum _PreviewViewport { desktop, tablet, mobile }

class StorefrontInAppPreviewDialog extends StatefulWidget {
  final Uri previewUri;
  final int? buildVersion;
  final String buildName;
  final bool enablePointAndEdit;
  final StorefrontPreviewEditStarter? onEditRequest;
  final StorefrontPreviewJobCompletionResolver? onJobCompleted;

  const StorefrontInAppPreviewDialog({
    super.key,
    required this.previewUri,
    required this.buildName,
    this.buildVersion,
    this.enablePointAndEdit = true,
    this.onEditRequest,
    this.onJobCompleted,
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
  late Uri _currentPreviewUri;
  late String _currentBuildName;
  int? _currentBuildVersion;
  StorefrontComponentSelection? _selection;
  PikiAiJob? _job;
  List<PikiAiJobEvent> _events = const [];
  _PreviewViewport _viewport = _PreviewViewport.desktop;
  bool _initializing = true;
  bool _loading = true;
  bool _inspectorReady = false;
  bool _inspecting = true;
  bool _startingEdit = false;
  String? _error;
  String? _jobError;
  String? _watchingJobId;

  Uri get _loadUri => widget.enablePointAndEdit
      ? _currentPreviewUri.replace(
          queryParameters: {
            ..._currentPreviewUri.queryParameters,
            'pikiInspect': '1',
          },
        )
      : _currentPreviewUri;

  @override
  void initState() {
    super.initState();
    _currentPreviewUri = widget.previewUri;
    _currentBuildName = widget.buildName;
    _currentBuildVersion = widget.buildVersion;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      if (widget.enablePointAndEdit) {
        _subscriptions.add(_controller.webMessage.listen(_handleWebMessage));
      }
      _subscriptions.add(
        _controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() => _loading = state == LoadingState.loading);
          if (state == LoadingState.navigationCompleted &&
              widget.enablePointAndEdit) {
            unawaited(_sendInspectorMode());
          }
        }),
      );
      await _controller.loadUrl(_loadUri.toString());
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
    for (var attempt = 0; attempt < 2 && decoded is String; attempt++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return;
      }
    }
    if (decoded is! Map) return;
    final data = Map<String, dynamic>.from(decoded);
    if (data['channel'] != 'piki-storefront-studio') {
      return;
    }
    if (data['type'] == 'inspector-ready') {
      if (mounted) setState(() => _inspectorReady = true);
      return;
    }
    if (data['type'] != 'section-selected' || data['selection'] is! Map) return;
    final selected = StorefrontComponentSelection.fromJson(
      Map<String, dynamic>.from(data['selection'] as Map),
    );
    if (!mounted) return;
    setState(() => _selection = selected);
  }

  Future<void> _sendInspectorMode() async {
    if (!_controller.value.isInitialized) return;
    try {
      await _controller.postWebMessage(
        jsonEncode({
          'channel': 'piki-storefront-studio',
          'type': 'set-inspector-mode',
          'enabled': _inspecting,
        }),
      );
    } catch (_) {
      // The page may still be replacing its document during navigation.
    }
  }

  Future<void> _setInspecting(bool value) async {
    if (_inspecting == value) return;
    setState(() {
      _inspecting = value;
      if (!value) _inspectorReady = false;
    });
    await _sendInspectorMode();
  }

  double? _viewportWidth(double availableWidth) {
    return switch (_viewport) {
      _PreviewViewport.desktop => null,
      _PreviewViewport.tablet => availableWidth.clamp(0, 768).toDouble(),
      _PreviewViewport.mobile => availableWidth.clamp(0, 390).toDouble(),
    };
  }

  bool get _isWorking => _startingEdit || _job?.isRunning == true;

  Future<void> _submit() async {
    final selection = _selection;
    final instruction = _instruction.text.trim();
    if (selection == null || instruction.length < 4) return;
    final starter = widget.onEditRequest;
    if (starter != null) {
      final request = StorefrontPreviewEditRequest(
        instruction: instruction,
        selection: selection,
      );
      setState(() {
        _startingEdit = true;
        _jobError = null;
      });
      try {
        final job = await starter(request);
        if (!mounted) return;
        setState(() {
          _job = job;
          _events = const [];
          _instruction.clear();
        });
        unawaited(_watchJob(job.id));
      } catch (error) {
        if (mounted) setState(() => _jobError = AppErrorMessage.from(error));
      } finally {
        if (mounted) setState(() => _startingEdit = false);
      }
      return;
    }
    Navigator.pop(
      context,
      StorefrontPreviewEditRequest(
        instruction: instruction,
        selection: selection,
      ),
    );
  }

  Future<void> _watchJob(String jobId) async {
    if (_watchingJobId == jobId) return;
    _watchingJobId = jobId;
    try {
      while (mounted) {
        final results = await Future.wait([
          PikiAiJobService.getJob(jobId),
          PikiAiJobService.getEvents(jobId),
        ]);
        if (!mounted) return;
        final job = results[0] as PikiAiJob;
        final events = results[1] as List<PikiAiJobEvent>;
        setState(() {
          _job = job;
          _events = events;
        });
        if (job.isDone) {
          if (!job.isFailed) await _loadCompletedPreview(job);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (error) {
      if (mounted) setState(() => _jobError = AppErrorMessage.from(error));
    } finally {
      if (_watchingJobId == jobId) _watchingJobId = null;
    }
  }

  Future<void> _loadCompletedPreview(PikiAiJob job) async {
    final resolver = widget.onJobCompleted;
    if (resolver == null) return;
    try {
      final completion = await resolver(job);
      if (!mounted || completion == null) return;
      setState(() {
        _currentPreviewUri = completion.previewUri;
        _currentBuildName = completion.buildName;
        _currentBuildVersion = completion.buildVersion;
        _selection = null;
        _inspectorReady = false;
        _loading = true;
      });
      await _controller.loadUrl(_loadUri.toString());
      await _sendInspectorMode();
    } catch (error) {
      if (mounted) setState(() => _jobError = AppErrorMessage.from(error));
    }
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
                _currentBuildVersion == null
                    ? 'Exact storefront preview'
                    : 'Exact storefront preview - v$_currentBuildVersion',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                _currentBuildName,
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
                _currentPreviewUri,
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
            if (widget.enablePointAndEdit)
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
                    _currentPreviewUri,
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
    final job = _job;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Point & edit with Piki',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !_inspecting
                                ? 'Browse mode · links and checkout work normally'
                                : _inspectorReady
                                ? 'Inspector connected · select any visible element'
                                : 'Connecting to the website inspector…',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (job != null || _jobError != null) ...[
                  if (job != null)
                    PikiActivityPanel(
                      job: job,
                      events: _events,
                      title: job.isRunning
                          ? 'Piki is editing this page'
                          : job.isFailed
                          ? 'Piki needs attention'
                          : 'Piki finished this edit',
                    ),
                  if (_jobError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _jobError!,
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                ],
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.ads_click_rounded, size: 17),
                      label: Text('Inspect'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.open_in_browser_rounded, size: 17),
                      label: Text('Browse'),
                    ),
                  ],
                  selected: {_inspecting},
                  onSelectionChanged: (value) => _setInspecting(value.first),
                ),
                const SizedBox(height: 8),
                Text(
                  _inspecting
                      ? 'Inspect headings, images, buttons, cards, navigation, forms, or complete sections.'
                      : 'Open the cart, checkout, account, or another page. Switch back to Inspect when the target is visible.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.35,
                  ),
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
                                'Select the exact element you want Piki to change.',
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
                                    'Selected element',
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
                              if (selected.scope != null ||
                                  selected.dimensions != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (selected.scope != null)
                                      'Inside ${selected.scope}',
                                    if (selected.dimensions != null)
                                      selected.dimensions!,
                                  ].join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                if (selected != null) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        [
                              'Change this style',
                              'Move this element',
                              'Improve mobile layout',
                              'Rewrite this text',
                            ]
                            .map(
                              (prompt) => ActionChip(
                                label: Text(prompt),
                                onPressed: () {
                                  _instruction.text = prompt;
                                  _instruction.selection =
                                      TextSelection.collapsed(
                                        offset: _instruction.text.length,
                                      );
                                  setState(() {});
                                },
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _instruction,
                  enabled: selected != null && !_isWorking,
                  minLines: 5,
                  maxLines: 9,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Tell Piki what to change',
                    alignLabelWithHint: true,
                    hintText:
                        'Example: Move this card above the hero, use two columns, and make its heading more elegant on mobile.',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Piki receives this element path, layout context, computed style, and current site build. Unrelated elements are preserved.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed:
                      selected != null &&
                          _instruction.text.trim().length >= 4 &&
                          !_isWorking
                      ? _submit
                      : null,
                  icon: _isWorking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  label: Text(
                    _isWorking ? 'Piki is working' : 'Edit selected element',
                  ),
                ),
              ],
            ),
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
