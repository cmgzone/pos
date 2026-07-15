import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/piki_ai_job_service.dart';
import '../../../core/services/storefront_theme_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/piki_activity_panel.dart';
import 'storefront_section_editor.dart';

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
            width: 440,
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

  Future<void> _customizeWithPiki(StorefrontTheme theme) async {
    final controller = TextEditingController();
    var fromScratch = true;
    final request = await showDialog<_PikiStorefrontRequest>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Build with Piki'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tell Piki what the customer website should feel like and what it should emphasize.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.dashboard_customize_rounded),
                      label: Text('Build complete store'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.tune_rounded),
                      label: Text('Refine current'),
                    ),
                  ],
                  selected: {fromScratch},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => fromScratch = selection.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 7,
                  decoration: InputDecoration(
                    labelText: fromScratch
                        ? 'Describe the complete storefront'
                        : 'Describe the changes',
                    hintText: fromScratch
                        ? 'Example: Build a warm modern grocery store with a strong welcome, category shortcuts, featured products, trust benefits, and WhatsApp help.'
                        : 'Example: Move featured products above categories and make the hero more minimal.',
                    helperText: fromScratch
                        ? 'Piki creates and orders the full page as a safe draft.'
                        : 'Piki keeps the structure and refines only what you request.',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
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
              _PikiStorefrontRequest(
                instruction: controller.text.trim(),
                fromScratch: fromScratch,
              ),
            ),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Build draft'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (request == null || request.instruction.length < 5) return;
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
        request.instruction,
        fromScratch: request.fromScratch,
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
          _errorRetry = () => _customizeWithPiki(theme);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _retryPikiJob() async {
    final job = _pikiJob;
    if (job == null || !job.isFailed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorRetry = null;
    });
    try {
      final retried = await PikiAiJobService.retryJob(job.id);
      if (!mounted) return;
      setState(() {
        _pikiJob = retried;
        _pikiEvents = const [];
      });
      _syncPikiPolling();
      unawaited(_refreshPikiJob());
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _errorRetry = _retryPikiJob;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWebsitePreview(StorefrontTheme theme) async {
    final uri = await StorefrontThemeService.previewUrl(theme);
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
            width: 520,
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

  Future<void> _publish(StorefrontTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish this theme?'),
        content: Text(
          '“${theme.name}” will replace the current live theme for this storefront. Other themes remain saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish'),
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

  Widget _buildPikiJobNotice() {
    final job = _pikiJob!;
    final colors = Theme.of(context).colorScheme;
    final title = job.isRunning
        ? 'Piki is building your storefront'
        : job.status == 'completed'
        ? 'Your storefront draft is ready'
        : 'Piki could not finish the storefront';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PikiActivityPanel(job: job, events: _pikiEvents, title: title),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              job.isRunning
                  ? Icons.cloud_done_outlined
                  : job.status == 'completed'
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
              size: 18,
              color: job.status == 'completed'
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                job.isRunning
                    ? 'This task runs in Piki Cloud. It continues if you leave this page or close the app.'
                    : job.status == 'completed'
                    ? 'Open the exact customer website preview, then publish only when it looks right.'
                    : (job.errorMessage ??
                          'You can retry the same saved request.'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            if (job.isRunning)
              TextButton.icon(
                onPressed: _pikiRefreshing ? null : _refreshPikiJob,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              )
            else if (job.status == 'completed')
              FilledButton.icon(
                onPressed: _busy ? null : _previewPikiDraft,
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text('Preview draft'),
              )
            else if (job.isFailed)
              FilledButton.icon(
                onPressed: _busy ? null : _retryPikiJob,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            if (!job.isRunning) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () => setState(() {
                  _pikiJob = null;
                  _pikiEvents = const [];
                }),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (_pikiJob != null) ...[
          const SizedBox(height: 12),
          _buildPikiJobNotice(),
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
    );
  }

  Widget _themeCard(StorefrontTheme theme) {
    final colors = Theme.of(context).colorScheme;
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
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: const Text('Preview website'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _customizeWithPiki(theme),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Piki build'),
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
                        icon: const Icon(Icons.publish_rounded, size: 18),
                        label: const Text('Publish'),
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

class _PikiStorefrontRequest {
  final String instruction;
  final bool fromScratch;

  const _PikiStorefrontRequest({
    required this.instruction,
    required this.fromScratch,
  });
}
