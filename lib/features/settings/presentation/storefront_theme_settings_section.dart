import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/piki_ai_job_service.dart';
import '../../../core/services/storefront_page_service.dart';
import '../../../core/services/storefront_theme_service.dart';
import '../../../core/utils/error_messages.dart';
import 'storefront_in_app_preview.dart';
import 'storefront_section_editor.dart';
import 'storefront_site_builder.dart';

enum _WebsiteWorkspaceView { studio, themes }

double _responsiveDialogWidth(BuildContext context, double maxWidth) {
  return (MediaQuery.sizeOf(context).width - 48)
      .clamp(240, maxWidth)
      .toDouble();
}

double _responsiveDialogHeight(BuildContext context, double maxHeight) {
  return (MediaQuery.sizeOf(context).height - 180)
      .clamp(280, maxHeight)
      .toDouble();
}

class StorefrontThemeSettingsSection extends StatefulWidget {
  const StorefrontThemeSettingsSection({super.key});

  @override
  State<StorefrontThemeSettingsSection> createState() =>
      _StorefrontThemeSettingsSectionState();
}

class _StorefrontThemeSettingsSectionState
    extends State<StorefrontThemeSettingsSection> {
  static const _branchId = 'main_branch';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  VoidCallback? _errorRetry;
  late String _storefrontType;
  List<StorefrontTheme> _themes = const [];
  List<StorefrontThemePreset> _presets = const [];
  StreamSubscription<StorefrontThemeChange>? _themeChanges;
  PikiAiJob? _pikiJob;
  List<PikiAiJobEvent> _pikiEvents = const [];
  Timer? _pikiPollTimer;
  bool _pikiRefreshing = false;
  _WebsiteWorkspaceView _workspaceView = _WebsiteWorkspaceView.themes;

  @override
  void initState() {
    super.initState();
    _storefrontType = _initialStorefrontType();
    _themeChanges = StorefrontThemeService.changes.listen(_onThemeChanged);
    _load();
    unawaited(_loadPikiJob());
  }

  @override
  void dispose() {
    _themeChanges?.cancel();
    _pikiPollTimer?.cancel();
    super.dispose();
  }

  String _initialStorefrontType() {
    final mode = LicenseService.currentSnapshot.entitlements.sellingMode
        .trim()
        .toLowerCase();
    if (mode == 'restaurant') return 'restaurant';
    if (mode == 'services' || mode == 'service') return 'services';
    return 'retail';
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _errorRetry = null;
      });
    }
    try {
      final result = await StorefrontThemeService.list(
        branchId: _branchId,
        storefrontType: _storefrontType,
      );
      if (!mounted) return;
      setState(() {
        _themes = result.themes;
        _presets = result.presets;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _errorRetry = () => _load();
      });
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _loadPikiJob() async {
    try {
      final jobs = await PikiAiJobService.listStorefrontThemeJobs();
      final now = DateTime.now();
      final matching = jobs.where((job) {
        final payload = job.payload;
        if (job.branchId != null && job.branchId != _branchId) return false;
        if (payload?['storefrontType']?.toString() != _storefrontType) {
          return false;
        }
        final createdAt = job.createdAt;
        return job.isRunning ||
            createdAt == null ||
            now.difference(createdAt).inHours < 48;
      }).toList();
      if (!mounted) return;
      if (matching.isEmpty) {
        _pikiPollTimer?.cancel();
        setState(() {
          _pikiJob = null;
          _pikiEvents = const [];
        });
        return;
      }
      final job = matching.first;
      final events = await PikiAiJobService.getEvents(job.id);
      if (!mounted) return;
      setState(() {
        _pikiJob = job;
        _pikiEvents = events;
      });
      _syncPikiPolling();
    } catch (_) {
      // Theme management remains available if background activity cannot load.
    }
  }

  void _syncPikiPolling() {
    _pikiPollTimer?.cancel();
    _pikiPollTimer = null;
    if (_pikiJob?.isRunning != true) return;
    _pikiPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshPikiJob()),
    );
  }

  Future<void> _refreshPikiJob() async {
    final current = _pikiJob;
    if (current == null || _pikiRefreshing) return;
    _pikiRefreshing = true;
    try {
      final job = await PikiAiJobService.getJob(current.id);
      final events = await PikiAiJobService.getEvents(current.id);
      if (!mounted) return;
      final justCompleted = current.isRunning && job.status == 'completed';
      setState(() {
        _pikiJob = job;
        _pikiEvents = _mergePikiEvents(_pikiEvents, events);
      });
      if (!job.isRunning) {
        _pikiPollTimer?.cancel();
        _pikiPollTimer = null;
      }
      if (justCompleted) {
        await _load(showLoading: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Piki finished the storefront draft. It is ready to preview.',
              ),
            ),
          );
        }
      }
    } catch (_) {
      // The saved backend job continues even when this polling request fails.
    } finally {
      _pikiRefreshing = false;
    }
  }

  List<PikiAiJobEvent> _mergePikiEvents(
    List<PikiAiJobEvent> current,
    List<PikiAiJobEvent> incoming,
  ) {
    final byId = <String, PikiAiJobEvent>{
      for (final event in current) event.id: event,
    };
    for (final event in incoming) {
      byId[event.id] = event;
    }
    final merged = byId.values.toList()
      ..sort(
        (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    return merged;
  }

  void _onThemeChanged(StorefrontThemeChange change) {
    final theme = change.theme;
    if (theme.branchId != _branchId ||
        theme.storefrontType != _storefrontType ||
        !mounted) {
      return;
    }
    setState(() {
      if (change.kind == StorefrontThemeChangeKind.delete) {
        _themes = _themes.where((item) => item.id != theme.id).toList();
        return;
      }
      _themes = [theme, ..._themes.where((item) => item.id != theme.id)];
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool reloadAfter = true,
    VoidCallback? retry,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorRetry = null;
    });
    try {
      await action();
      if (reloadAfter) await _load(showLoading: false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _errorRetry = retry;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTheme() async {
    final nameController = TextEditingController(
      text: '${_typeLabel(_storefrontType)} theme ${_themes.length + 1}',
    );
    var preset = _presets.isEmpty ? 'studio' : _presets.first.id;
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add storefront theme'),
          content: SizedBox(
            width: _responsiveDialogWidth(context, 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Theme name'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: preset,
                  decoration: const InputDecoration(
                    labelText: 'Starting style',
                  ),
                  items: _presets
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => preset = value);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _presets
                          .where((item) => item.id == preset)
                          .firstOrNull
                          ?.description ??
                      'Start with a safe Piki storefront layout.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create draft'),
            ),
          ],
        ),
      ),
    );
    final name = nameController.text.trim();
    nameController.dispose();
    if (create != true || name.isEmpty) return;
    await _run(() async {
      await StorefrontThemeService.create(
        branchId: _branchId,
        storefrontType: _storefrontType,
        name: name,
        preset: preset,
      );
    });
  }


  Future<void> _startPikiThemeJob(
    StorefrontTheme theme,
    String instruction, {
    required bool fromScratch,
    required VoidCallback retry,
  }) async {
    if (_pikiJob?.isRunning == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Piki is already building a storefront in the cloud.'),
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorRetry = null;
    });
    try {
      final job = await PikiAiJobService.createStorefrontThemeJob(
        theme.id,
        instruction,
        fromScratch: fromScratch,
      );
      if (!mounted) return;
      setState(() {
        _pikiJob = job;
        _pikiEvents = const [];
      });
      _syncPikiPolling();
      unawaited(_refreshPikiJob());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Piki is building in the cloud. You can leave this page or close the app.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _errorRetry = retry;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startGeneratedSiteEdit(
    StorefrontPreviewEditRequest edit,
  ) async {
    final selection = edit.selection;
    final buildId = selection.siteBuildId;
    if (buildId == null || _pikiJob?.isRunning == true) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorRetry = null;
    });
    try {
      final job = await PikiAiJobService.createStorefrontSiteJob(
        edit.instruction,
        branchId: _branchId,
        storefrontType: _storefrontType,
        parentBuildId: buildId,
        siteMode: selection.siteMode,
        selectedProductId: selection.selectedProductId,
        selectionContext: selection.toJson(),
      );
      if (!mounted) return;
      setState(() {
        _pikiJob = job;
        _pikiEvents = const [];
      });
      _syncPikiPolling();
      unawaited(_refreshPikiJob());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Piki is editing the selected element in the saved site build. You can close the app while it works.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _errorRetry = _previewPikiDraft;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PikiAiJob> _createGeneratedSiteEditJob(
    StorefrontPreviewEditRequest edit,
  ) async {
    final selection = edit.selection;
    final buildId = selection.siteBuildId;
    if (buildId == null) {
      throw Exception('Select a generated website element first.');
    }
    if (_pikiJob?.isRunning == true) {
      throw Exception('Piki is already editing this storefront.');
    }
    final job = await PikiAiJobService.createStorefrontSiteJob(
      edit.instruction,
      branchId: _branchId,
      storefrontType: _storefrontType,
      parentBuildId: buildId,
      siteMode: selection.siteMode,
      selectedProductId: selection.selectedProductId,
      selectionContext: selection.toJson(),
    );
    if (mounted) {
      setState(() {
        _pikiJob = job;
        _pikiEvents = const [];
      });
      _syncPikiPolling();
      unawaited(_refreshPikiJob());
    }
    return job;
  }

  Future<PikiAiJob> _createThemePreviewEditJob(
    StorefrontTheme theme,
    StorefrontPreviewEditRequest edit,
  ) async {
    final selection = edit.selection;
    if (selection.siteBuildId != null) {
      return _createGeneratedSiteEditJob(edit);
    }
    if (_pikiJob?.isRunning == true) {
      throw Exception('Piki is already editing this storefront.');
    }
    final instruction =
        '''
Edit the selected ${selection.label} component to satisfy this request: ${edit.instruction}

Selected component metadata: ${jsonEncode(selection.toJson())}
Preserve every unrelated website section, existing brand choice, checkout setting, and live catalogue behavior.
''';
    final job = await PikiAiJobService.createStorefrontThemeJob(
      theme.id,
      instruction,
      fromScratch: false,
    );
    if (mounted) {
      setState(() {
        _pikiJob = job;
        _pikiEvents = const [];
      });
      _syncPikiPolling();
      unawaited(_refreshPikiJob());
    }
    return job;
  }

  Future<StorefrontPreviewJobCompletion?> _resolvePreviewEditCompletion(
    PikiAiJob job,
  ) async {
    if (job.jobType == 'storefront_site') {
      final value = job.result?['build'];
      if (value is! Map) {
        throw Exception(
          'Piki finished, but the generated site build is missing.',
        );
      }
      final build = StorefrontSiteBuild.fromJson(
        Map<String, dynamic>.from(value),
      );
      await _load(showLoading: false);
      final uri = await StorefrontPageService.siteBuildPreviewUrl(build.id);
      return StorefrontPreviewJobCompletion(
        previewUri: uri,
        buildVersion: build.version,
        buildName: build.name,
      );
    }
    if (job.jobType == 'storefront_theme') {
      await _load(showLoading: false);
      final theme = _pikiResultTheme(job);
      if (theme == null) {
        throw Exception(
          'Piki finished, but the saved theme could not be loaded.',
        );
      }
      final uri = await StorefrontThemeService.previewUrl(theme);
      return StorefrontPreviewJobCompletion(
        previewUri: uri,
        buildName: theme.name,
      );
    }
    return null;
  }

  StorefrontTheme? _pikiResultTheme(PikiAiJob job) {
    final value = job.result?['theme'];
    if (value is Map) {
      return StorefrontTheme.fromJson(Map<String, dynamic>.from(value));
    }
    final themeId = job.result?['themeId']?.toString();
    return _themes.where((theme) => theme.id == themeId).firstOrNull;
  }

  Future<void> _previewPikiDraft() async {
    final job = _pikiJob;
    if (job == null || job.status != 'completed') return;
    if (job.jobType == 'storefront_site') {
      final value = job.result?['build'];
      if (value is! Map) {
        setState(() {
          _error = 'Piki finished, but the generated site build is missing.';
          _errorRetry = _previewPikiDraft;
        });
        return;
      }
      final build = StorefrontSiteBuild.fromJson(
        Map<String, dynamic>.from(value),
      );
      StorefrontPreviewEditRequest? edit;
      await _run(
        () async {
          final uri = await StorefrontPageService.siteBuildPreviewUrl(build.id);
          if (!mounted) return;
          if (!Platform.isWindows) {
            final opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (!opened) {
              throw Exception('Could not open the generated-site preview.');
            }
            return;
          }
          edit = await showDialog<StorefrontPreviewEditRequest>(
            context: context,
            barrierDismissible: false,
            builder: (context) => StorefrontInAppPreviewDialog(
              previewUri: uri,
              buildVersion: build.version,
              buildName: build.name,
              onEditRequest: _createGeneratedSiteEditJob,
              onJobCompleted: _resolvePreviewEditCompletion,
            ),
          );
        },
        reloadAfter: false,
        retry: _previewPikiDraft,
      );
      if (edit != null && mounted) await _startGeneratedSiteEdit(edit!);
      return;
    }
    final theme = _pikiResultTheme(job);
    if (theme == null) {
      await _load(showLoading: false);
    }
    final refreshedTheme = _pikiResultTheme(job);
    if (refreshedTheme == null) {
      setState(() {
        _error = 'Piki finished, but the saved theme could not be loaded.';
        _errorRetry = _previewPikiDraft;
      });
      return;
    }
    await _run(
      () => _openWebsitePreview(refreshedTheme),
      reloadAfter: false,
      retry: _previewPikiDraft,
    );
  }


  Future<void> _openWebsitePreview(StorefrontTheme theme) async {
    final uri = await StorefrontThemeService.previewUrl(theme);
    if (Platform.isWindows && mounted) {
      final edit = await showDialog<StorefrontPreviewEditRequest>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StorefrontInAppPreviewDialog(
          previewUri: uri,
          buildName: theme.name,
          enablePointAndEdit: true,
          onEditRequest: (edit) => _createThemePreviewEditJob(theme, edit),
          onJobCompleted: _resolvePreviewEditCompletion,
        ),
      );
      if (edit != null && mounted) {
        final selection = edit.selection;
        if (selection.siteBuildId != null) {
          await _startGeneratedSiteEdit(edit);
          return;
        }
        final instruction =
            '''
Edit the selected ${selection.label} component to satisfy this request: ${edit.instruction}

Selected component metadata: ${jsonEncode(selection.toJson())}
Preserve every unrelated website section, existing brand choice, checkout setting, and live catalogue behavior.
''';
        await _startPikiThemeJob(
          theme,
          instruction,
          fromScratch: false,
          retry: () => _preview(theme),
        );
      }
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw Exception('Could not open the exact storefront website preview.');
    }
  }

  Future<void> _preview(StorefrontTheme theme) {
    return _run(
      () => _openWebsitePreview(theme),
      reloadAfter: false,
      retry: () => _preview(theme),
    );
  }

  Future<void> _editCheckout(StorefrontTheme theme) async {
    var manual = theme.checkout.paymentMethods.contains('manual');
    var mpesa = theme.checkout.paymentMethods.contains('mpesa');
    var pickup = theme.checkout.fulfillmentMethods.contains('pickup');
    var delivery = theme.checkout.fulfillmentMethods.contains('delivery');
    var showAddress = theme.checkout.showDeliveryAddress;
    var showNote = theme.checkout.showOrderNote;
    var showTracking = theme.checkout.showOrderTracking;
    final title = TextEditingController(text: theme.checkout.checkoutTitle);
    final button = TextEditingController(
      text: theme.checkout.checkoutButtonLabel,
    );
    final success = TextEditingController(text: theme.checkout.successMessage);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customize checkout'),
          content: SizedBox(
            width: _responsiveDialogWidth(context, 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Payment methods',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: manual,
                    title: const Text('Pay on confirmation'),
                    onChanged: (value) =>
                        setDialogState(() => manual = value ?? true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: mpesa,
                    title: const Text('M-Pesa'),
                    subtitle: const Text(
                      'Shown only after the business gateway is active.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => mpesa = value ?? false),
                  ),
                  const Divider(),
                  Text(
                    'Fulfillment',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: pickup,
                    title: const Text('Pickup'),
                    onChanged: (value) =>
                        setDialogState(() => pickup = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: delivery,
                    title: const Text('Delivery'),
                    onChanged: (value) =>
                        setDialogState(() => delivery = value ?? false),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showAddress,
                    title: const Text('Ask for delivery address'),
                    onChanged: (value) =>
                        setDialogState(() => showAddress = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showNote,
                    title: const Text('Show order note'),
                    onChanged: (value) =>
                        setDialogState(() => showNote = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showTracking,
                    title: const Text('Show order tracking'),
                    onChanged: (value) =>
                        setDialogState(() => showTracking = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Checkout title',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: button,
                    decoration: const InputDecoration(
                      labelText: 'Button label',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: success,
                    decoration: const InputDecoration(
                      labelText: 'Success message',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if ((!manual && !mpesa) || (!pickup && !delivery)) return;
                Navigator.pop(context, true);
              },
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
    final checkoutTitle = title.text.trim();
    final checkoutButton = button.text.trim();
    final successMessage = success.text.trim();
    title.dispose();
    button.dispose();
    success.dispose();
    if (save != true) return;
    await _run(() async {
      final draft = theme.isPublished
          ? await StorefrontThemeService.duplicate(
              theme.id,
              name: '${theme.name} checkout draft',
            )
          : theme;
      await StorefrontThemeService.update(draft.id, {
        'checkout': {
          'paymentMethods': [if (manual) 'manual', if (mpesa) 'mpesa'],
          'defaultPaymentMethod': manual ? 'manual' : 'mpesa',
          'fulfillmentMethods': [
            if (pickup) 'pickup',
            if (delivery) 'delivery',
          ],
          'defaultFulfillmentMethod': pickup ? 'pickup' : 'delivery',
          'showDeliveryAddress': showAddress,
          'showOrderNote': showNote,
          'showOrderTracking': showTracking,
          'checkoutTitle': checkoutTitle,
          'checkoutButtonLabel': checkoutButton,
          'successMessage': successMessage,
        },
      });
    });
  }

  Future<void> _editSections(StorefrontTheme theme) async {
    final sections = await showStorefrontSectionEditor(context, theme);
    if (sections == null || !mounted) return;
    await _run(() async {
      final draft = theme.isPublished
          ? await StorefrontThemeService.duplicate(
              theme.id,
              name: '${theme.name} layout draft',
            )
          : theme;
      await StorefrontThemeService.update(draft.id, {
        'sections': sections,
        'source': 'manual',
      });
    });
  }

  Future<void> _editDesign(StorefrontTheme theme) async {
    final background = TextEditingController(
      text: theme.design.backgroundColor,
    );
    final text = TextEditingController(text: theme.design.textColor);
    final surface = TextEditingController(text: theme.design.surfaceColor);
    final accent = TextEditingController(text: theme.design.accentColor);
    var headingFont = theme.design.headingFontFamily;
    var bodyFont = theme.design.bodyFontFamily;
    var headingScale = theme.design.headingScale;
    var contentWidth = theme.design.contentWidth;
    var sectionSpacing = theme.design.sectionSpacing;
    var buttonStyle = theme.design.buttonStyle;
    var navigationStyle = theme.design.navigationStyle;
    var iconStyle = theme.design.iconStyle;
    var motionStyle = theme.design.motionStyle;
    var catalogLayout = theme.design.catalogLayout;
    var heroStyle = theme.design.heroStyle;
    var cardStyle = theme.design.cardStyle;
    var imageRatio = theme.design.imageRatio;
    var cornerStyle = theme.design.cornerStyle;
    var productColumns = theme.design.productColumns;
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget dropdown({
            required String label,
            required String value,
            required List<(String, String)> options,
            required ValueChanged<String> onChanged,
          }) {
            return DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: value,
              decoration: InputDecoration(labelText: label),
              items: options
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                  )
                  .toList(),
              onChanged: (next) {
                if (next != null) setDialogState(() => onChanged(next));
              },
            );
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.palette_outlined),
                SizedBox(width: 10),
                Text('Design system'),
              ],
            ),
            content: SizedBox(
              width: _responsiveDialogWidth(context, 760),
              height: _responsiveDialogHeight(context, 590),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'These global controls keep every page consistent. Choose whether product categories appear above the catalogue or in a real desktop sidebar. Section-level positioning remains available in Edit sections.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    _builderGroupTitle(context, 'Typography'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: dropdown(
                            label: 'Heading font',
                            value: headingFont,
                            options: _fontOptions,
                            onChanged: (value) => headingFont = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: dropdown(
                            label: 'Body font',
                            value: bodyFont,
                            options: _fontOptions,
                            onChanged: (value) => bodyFont = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: dropdown(
                            label: 'Heading scale',
                            value: headingScale,
                            options: const [
                              ('compact', 'Compact'),
                              ('balanced', 'Balanced'),
                              ('display', 'Large display'),
                            ],
                            onChanged: (value) => headingScale = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _builderGroupTitle(context, 'Layout & rhythm'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: dropdown(
                            label: 'Content width',
                            value: contentWidth,
                            options: const [
                              ('compact', 'Compact'),
                              ('standard', 'Standard'),
                              ('wide', 'Wide'),
                              ('full', 'Full canvas'),
                            ],
                            onChanged: (value) => contentWidth = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: dropdown(
                            label: 'Section spacing',
                            value: sectionSpacing,
                            options: const [
                              ('tight', 'Tight'),
                              ('standard', 'Standard'),
                              ('airy', 'Airy'),
                            ],
                            onChanged: (value) => sectionSpacing = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: dropdown(
                            label: 'Category navigation',
                            value: catalogLayout,
                            options: const [
                              ('topbar', 'Above products'),
                              ('sidebar', 'Left sidebar'),
                            ],
                            onChanged: (value) => catalogLayout = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: productColumns,
                            decoration: const InputDecoration(
                              labelText: 'Product columns',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 2,
                                child: Text('2 columns'),
                              ),
                              DropdownMenuItem(
                                value: 3,
                                child: Text('3 columns'),
                              ),
                              DropdownMenuItem(
                                value: 4,
                                child: Text('4 columns'),
                              ),
                              DropdownMenuItem(
                                value: 5,
                                child: Text('5 columns'),
                              ),
                            ],
                            onChanged: (value) => setDialogState(
                              () => productColumns = value ?? productColumns,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _builderGroupTitle(context, 'Components'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: dropdown(
                            label: 'Hero',
                            value: heroStyle,
                            options: const [
                              ('cover', 'Cover'),
                              ('split', 'Split'),
                              ('minimal', 'Minimal'),
                            ],
                            onChanged: (value) => heroStyle = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dropdown(
                            label: 'Cards',
                            value: cardStyle,
                            options: const [
                              ('bordered', 'Bordered'),
                              ('elevated', 'Elevated'),
                              ('minimal', 'Minimal'),
                            ],
                            onChanged: (value) => cardStyle = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dropdown(
                            label: 'Images',
                            value: imageRatio,
                            options: const [
                              ('square', 'Square'),
                              ('portrait', 'Portrait'),
                              ('landscape', 'Landscape'),
                            ],
                            onChanged: (value) => imageRatio = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dropdown(
                            label: 'Corners',
                            value: cornerStyle,
                            options: const [
                              ('sharp', 'Sharp'),
                              ('soft', 'Soft'),
                              ('rounded', 'Rounded'),
                              ('pill', 'Pill'),
                            ],
                            onChanged: (value) => cornerStyle = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: dropdown(
                            label: 'Buttons',
                            value: buttonStyle,
                            options: const [
                              ('solid', 'Solid'),
                              ('outline', 'Outline'),
                              ('soft', 'Soft'),
                            ],
                            onChanged: (value) => buttonStyle = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dropdown(
                            label: 'Navigation',
                            value: navigationStyle,
                            options: const [
                              ('minimal', 'Minimal'),
                              ('centered', 'Centered'),
                              ('expanded', 'Expanded'),
                            ],
                            onChanged: (value) => navigationStyle = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dropdown(
                            label: 'Icons',
                            value: iconStyle,
                            options: const [
                              ('plain', 'Plain'),
                              ('boxed', 'Boxed'),
                              ('circle', 'Circle'),
                            ],
                            onChanged: (value) => iconStyle = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dropdown(
                            label: 'Motion',
                            value: motionStyle,
                            options: const [
                              ('none', 'None'),
                              ('subtle', 'Subtle'),
                              ('expressive', 'Expressive'),
                            ],
                            onChanged: (value) => motionStyle = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _builderGroupTitle(context, 'Colour palette'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: background,
                            decoration: const InputDecoration(
                              labelText: 'Background',
                              hintText: '#F8F7F3',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: text,
                            decoration: const InputDecoration(
                              labelText: 'Text',
                              hintText: '#191916',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: surface,
                            decoration: const InputDecoration(
                              labelText: 'Surface',
                              hintText: '#FFFFFF',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: accent,
                            decoration: const InputDecoration(
                              labelText: 'Accent',
                              hintText: '#D14343',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save design draft'),
              ),
            ],
          );
        },
      ),
    );
    final design = {
      ...theme.design.toJson(),
      'backgroundColor': background.text.trim(),
      'textColor': text.text.trim(),
      'surfaceColor': surface.text.trim(),
      'accentColor': accent.text.trim(),
      'fontFamily': bodyFont,
      'headingFontFamily': headingFont,
      'bodyFontFamily': bodyFont,
      'headingScale': headingScale,
      'contentWidth': contentWidth,
      'sectionSpacing': sectionSpacing,
      'buttonStyle': buttonStyle,
      'navigationStyle': navigationStyle,
      'iconStyle': iconStyle,
      'motionStyle': motionStyle,
      'catalogLayout': catalogLayout,
      'heroStyle': heroStyle,
      'cardStyle': cardStyle,
      'imageRatio': imageRatio,
      'cornerStyle': cornerStyle,
      'productColumns': productColumns,
    };
    background.dispose();
    text.dispose();
    surface.dispose();
    accent.dispose();
    if (save != true) return;
    await _run(() async {
      final draft = theme.isPublished
          ? await StorefrontThemeService.duplicate(
              theme.id,
              name: '${theme.name} design draft',
            )
          : theme;
      await StorefrontThemeService.update(draft.id, {
        'design': design,
        'source': 'manual',
      });
    });
  }

  bool _isThemeRestoreCandidate(StorefrontTheme theme) {
    final live = _themes.where((item) => item.isPublished).firstOrNull;
    if (theme.isPublished || live == null || live.id == theme.id) return false;
    final themeUpdated = theme.updatedAt;
    final liveUpdated = live.updatedAt;
    return themeUpdated == null ||
        liveUpdated == null ||
        themeUpdated.isBefore(liveUpdated);
  }

  Future<void> _publish(StorefrontTheme theme) async {
    final restoring = _isThemeRestoreCandidate(theme);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(restoring ? 'Restore this theme?' : 'Publish this theme?'),
        content: Text(
          restoring
              ? 'This will revert the customer storefront to ${theme.name}. The current live theme remains saved.'
              : '${theme.name} will replace the current live theme for this storefront. Other themes remain saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(
              restoring ? Icons.history_rounded : Icons.publish_rounded,
            ),
            label: Text(restoring ? 'Restore theme' : 'Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await StorefrontThemeService.publish(theme.id);
    });
  }

  Future<void> _delete(StorefrontTheme theme) async {
    if (theme.isPublished) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text('Delete “${theme.name}”? This cannot be undone.'),
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
    if (confirmed != true) return;
    await _run(() => StorefrontThemeService.delete(theme.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final previewTheme =
        _themes.where((theme) => theme.isPublished).firstOrNull ??
        _themes.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _websiteWorkspaceHeader(colors, previewTheme),
        const SizedBox(height: 18),
        if (_workspaceView == _WebsiteWorkspaceView.studio)
          StorefrontSiteBuilder(
            key: ValueKey('site-builder-$_storefrontType'),
            storefrontType: _storefrontType,
            onPreviewCurrentStore: previewTheme == null
                ? null
                : () => unawaited(_preview(previewTheme)),
          )
        else ...[
          Row(
            children: [
              Icon(Icons.home_work_outlined, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Homepage themes',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Control the global design system, homepage structure, and checkout.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      initialValue: _storefrontType,
                      decoration: const InputDecoration(
                        labelText: 'Storefront type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'retail',
                          child: Text('Products'),
                        ),
                        DropdownMenuItem(
                          value: 'services',
                          child: Text('Services'),
                        ),
                        DropdownMenuItem(
                          value: 'restaurant',
                          child: Text('Restaurant'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null || value == _storefrontType) {
                                return;
                              }
                              _pikiPollTimer?.cancel();
                              setState(() => _storefrontType = value);
                              _load();
                              unawaited(_loadPikiJob());
                            },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createTheme,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add theme'),
                  ),
                  Text(
                    '${_themes.length} saved · unlimited drafts',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Preview opens the real customer website.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildErrorNotice(),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_themes.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.web_asset_off_outlined,
                      size: 42,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text('No saved themes yet'),
                    const SizedBox(height: 6),
                    Text(
                      'Create as many themes as you need, then publish one when it is ready.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _themes
                      .map(
                        (theme) =>
                            SizedBox(width: width, child: _themeCard(theme)),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _websiteWorkspaceHeader(
    ColorScheme colors,
    StorefrontTheme? previewTheme,
  ) {
    final liveTheme = _themes.where((theme) => theme.isPublished).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary.withValues(alpha: 0.11), colors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final intro = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.language_rounded, color: colors.onPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Website studio',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      liveTheme == null
                          ? 'Build the customer website, configure checkout, preview every change, then publish.'
                          : '${liveTheme.name} is live. Drafts stay private until you publish them.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final preview = FilledButton.tonalIcon(
            onPressed: previewTheme == null || _busy
                ? null
                : () => unawaited(_preview(previewTheme)),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(
              Platform.isWindows ? 'Preview & inspect' : 'Preview website',
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                intro,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: preview),
              ] else
                Row(
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 18),
                    preview,
                  ],
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _websiteWorkspaceTab(
                        colors: colors,
                        value: _WebsiteWorkspaceView.themes,
                        icon: Icons.tune_rounded,
                        label: compact ? 'Manage' : 'Themes & checkout',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _websiteWorkspaceTab({
    required ColorScheme colors,
    required _WebsiteWorkspaceView value,
    required IconData icon,
    required String label,
  }) {
    final selected = _workspaceView == value;
    return Material(
      color: selected ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: () => setState(() => _workspaceView = value),
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeCard(StorefrontTheme theme) {
    final colors = Theme.of(context).colorScheme;
    final restoring = _isThemeRestoreCandidate(theme);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 96,
            color: _color(theme.design.backgroundColor, colors.surface),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                height: 34,
                width: 118,
                decoration: BoxDecoration(
                  color: _color(
                    theme.design.surfaceColor,
                    colors.surfaceContainer,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _color(
                      theme.design.borderColor,
                      colors.outlineVariant,
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 10),
                    width: 42,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _color(theme.design.accentColor, colors.primary),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        theme.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Chip(
                      avatar: Icon(
                        theme.isPublished
                            ? Icons.public_rounded
                            : Icons.edit_note_rounded,
                        size: 16,
                      ),
                      label: Text(theme.isPublished ? 'Live' : 'Draft'),
                    ),
                  ],
                ),
                Text(
                  '${theme.sections.where((section) => section.enabled).length} sections · ${theme.design.heroStyle} hero · ${theme.design.cardStyle} cards',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _preview(theme),
                      icon: Icon(
                        Platform.isWindows
                            ? Icons.web_asset_rounded
                            : Icons.open_in_browser_rounded,
                        size: 18,
                      ),
                      label: Text(
                        Platform.isWindows
                            ? 'Preview in app'
                            : 'Preview website',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _editDesign(theme),
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('Design system'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _editSections(theme),
                      icon: const Icon(Icons.view_quilt_outlined, size: 18),
                      label: const Text('Edit sections'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _editCheckout(theme),
                      icon: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        size: 18,
                      ),
                      label: const Text('Checkout'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await StorefrontThemeService.duplicate(theme.id);
                            }),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Duplicate'),
                    ),
                    if (!theme.isPublished)
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _publish(theme),
                        icon: Icon(
                          restoring
                              ? Icons.history_rounded
                              : Icons.publish_rounded,
                          size: 18,
                        ),
                        label: Text(restoring ? 'Restore' : 'Publish'),
                      ),
                    if (!theme.isPublished)
                      IconButton(
                        tooltip: 'Delete draft',
                        onPressed: _busy ? null : () => _delete(theme),
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

  Color _color(String value, Color fallback) {
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null || hex.length != 6
        ? fallback
        : Color(0xff000000 | parsed);
  }

  String _typeLabel(String type) => switch (type) {
    'services' => 'Services',
    'restaurant' => 'Restaurant',
    _ => 'Product',
  };

  String _message(Object error) {
    return AppErrorMessage.from(
      error,
      fallback: 'The storefront action could not be completed. Try again.',
    );
  }

  Widget _buildErrorNotice() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.error.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded, color: colors.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storefront action could not finish',
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _error!,
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (_errorRetry != null)
            TextButton(
              onPressed: _busy ? null : _errorRetry,
              child: const Text('Retry'),
            ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () => setState(() {
              _error = null;
              _errorRetry = null;
            }),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

const _fontOptions = <(String, String)>[
  ('inter', 'Inter'),
  ('modern', 'Modern sans'),
  ('serif', 'Editorial serif'),
  ('rounded', 'Friendly rounded'),
  ('poppins', 'Poppins'),
  ('playfair', 'Playfair Display'),
  ('montserrat', 'Montserrat'),
  ('nunito', 'Nunito'),
  ('oswald', 'Oswald'),
  ('merriweather', 'Merriweather'),
  ('system', 'System'),
];

Widget _builderGroupTitle(BuildContext context, String label) {
  return Row(
    children: [
      Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(child: Divider()),
    ],
  );
}
