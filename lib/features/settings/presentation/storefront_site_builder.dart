import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/piki_ai_job_service.dart';
import '../../../core/services/storefront_page_service.dart';
import '../../../core/services/storefront_theme_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/piki_activity_panel.dart';
import 'storefront_section_editor.dart';
import 'storefront_in_app_preview.dart';

class StorefrontSiteBuilder extends StatefulWidget {
  final String storefrontType;
  final VoidCallback? onPreviewCurrentStore;

  const StorefrontSiteBuilder({
    super.key,
    required this.storefrontType,
    this.onPreviewCurrentStore,
  });

  @override
  State<StorefrontSiteBuilder> createState() => _StorefrontSiteBuilderState();
}

class _StorefrontSiteBuilderState extends State<StorefrontSiteBuilder> {
  static const _branchId = 'main_branch';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<StorefrontPage> _pages = const [];
  StorefrontConnection? _connection;
  List<StorefrontSiteBuild> _siteBuilds = const [];
  List<StorefrontBuilderItem> _siteBuilderItems = const [];
  PikiAiJob? _siteJob;
  List<PikiAiJobEvent> _siteEvents = const [];
  String? _watchingSiteJobId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StorefrontSiteBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storefrontType != widget.storefrontType) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        StorefrontPageService.list(
          branchId: _branchId,
          storefrontType: widget.storefrontType,
        ),
        StorefrontPageService.connection(branchId: _branchId),
        StorefrontPageService.listSiteBuilds(
          branchId: _branchId,
          storefrontType: widget.storefrontType,
        ),
        PikiAiJobService.listStorefrontSiteJobs(),
        StorefrontPageService.listSiteBuilderItems(
          branchId: _branchId,
          storefrontType: widget.storefrontType,
        ).catchError((_) => <StorefrontBuilderItem>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _pages = results[0] as List<StorefrontPage>;
        _connection = results[1] as StorefrontConnection?;
        _siteBuilds = results[2] as List<StorefrontSiteBuild>;
        final jobs = results[3] as List<PikiAiJob>;
        _siteJob = _latestRelevantSiteJob(jobs);
        _siteBuilderItems = results[4] as List<StorefrontBuilderItem>;
      });
      if (_siteJob != null) unawaited(_watchSiteJob(_siteJob!.id));
    } catch (error) {
      if (mounted) setState(() => _error = AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  PikiAiJob? _latestRelevantSiteJob(List<PikiAiJob> jobs) {
    for (final job in jobs) {
      final payload = job.payload ?? const <String, dynamic>{};
      final storefrontType = payload['storefrontType']?.toString();
      if (storefrontType != null && storefrontType != widget.storefrontType) {
        continue;
      }
      return job.isRunning || job.isFailed ? job : null;
    }
    return null;
  }

  StorefrontSiteBuild? get _publishedSiteBuild {
    for (final build in _siteBuilds) {
      if (build.isPublished) return build;
    }
    return null;
  }

  Future<void> _refreshSiteBuilds() async {
    final builds = await StorefrontPageService.listSiteBuilds(
      branchId: _branchId,
      storefrontType: widget.storefrontType,
    );
    if (mounted) setState(() => _siteBuilds = builds);
  }

  Future<void> _openSiteCompiler([StorefrontSiteBuild? baseBuild]) async {
    final selectedBase = baseBuild ?? _publishedSiteBuild;
    final request = await showDialog<_SiteCompilerRequest>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SiteCompilerDialog(
        baseBuild: selectedBase,
        items: _siteBuilderItems,
      ),
    );
    if (request == null) return;
    await _startSiteCompilerRequest(request);
  }

  Future<void> _startSiteCompilerRequest(_SiteCompilerRequest request) async {
    await _run(() async {
      final job = await PikiAiJobService.createStorefrontSiteJob(
        request.instruction,
        branchId: _branchId,
        storefrontType: widget.storefrontType,
        parentBuildId: request.parentBuildId,
        siteMode: request.siteMode,
        selectedProductId: request.selectedProductId,
        selectionContext: request.selectionContext,
      );
      if (!mounted) return;
      setState(() {
        _siteJob = job;
        _siteEvents = const [];
      });
      unawaited(_watchSiteJob(job.id));
    });
  }

  Future<void> _retrySiteCompilerJob() async {
    final job = _siteJob;
    if (job == null || !job.isFailed || _busy) return;
    await _run(() async {
      final retried = await PikiAiJobService.retryJob(job.id);
      if (!mounted) return;
      setState(() {
        _siteJob = retried;
        _siteEvents = const [];
      });
      unawaited(_watchSiteJob(retried.id));
    });
  }

  Future<void> _watchSiteJob(String jobId) async {
    if (_watchingSiteJobId == jobId) return;
    _watchingSiteJobId = jobId;
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
          _siteJob = job;
          _siteEvents = events;
        });
        if (job.isDone) {
          if (!job.isFailed) await _refreshSiteBuilds();
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (error) {
      if (mounted) setState(() => _error = AppErrorMessage.from(error));
    } finally {
      if (_watchingSiteJobId == jobId) _watchingSiteJobId = null;
    }
  }

  bool _isRestoreCandidate(StorefrontSiteBuild build) {
    final live = _publishedSiteBuild;
    return !build.isPublished &&
        (build.status == 'archived' ||
            (live != null && build.version < live.version));
  }

  Future<PikiAiJob> _createPreviewSiteEditJob(
    StorefrontSiteBuild build,
    StorefrontPreviewEditRequest edit,
  ) async {
    final selection = edit.selection;
    final job = await PikiAiJobService.createStorefrontSiteJob(
      edit.instruction,
      branchId: _branchId,
      storefrontType: widget.storefrontType,
      parentBuildId: selection.siteBuildId ?? build.id,
      siteMode:
          selection.siteMode ??
          (build.singleProductId == null ? 'catalog' : 'single_product'),
      selectedProductId: selection.selectedProductId ?? build.singleProductId,
      selectionContext: selection.toJson(),
    );
    if (mounted) {
      setState(() {
        _siteJob = job;
        _siteEvents = const [];
      });
      unawaited(_watchSiteJob(job.id));
    }
    return job;
  }

  Future<StorefrontPreviewJobCompletion?> _resolveSitePreviewEditCompletion(
    PikiAiJob job,
  ) async {
    final value = job.result?['build'];
    if (value is! Map) {
      throw Exception(
        'Piki finished, but the generated site build is missing.',
      );
    }
    final build = StorefrontSiteBuild.fromJson(
      Map<String, dynamic>.from(value),
    );
    await _refreshSiteBuilds();
    final uri = await StorefrontPageService.siteBuildPreviewUrl(build.id);
    return StorefrontPreviewJobCompletion(
      previewUri: uri,
      buildVersion: build.version,
      buildName: build.name,
    );
  }

  Future<void> _previewSiteBuild(StorefrontSiteBuild build) async {
    Uri? uri;
    await _run(() async {
      uri = await StorefrontPageService.siteBuildPreviewUrl(build.id);
    });
    if (!mounted || uri == null) return;
    if (!Platform.isWindows) {
      if (!await launchUrl(uri!, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          setState(
            () => _error = 'Could not open the exact generated-site preview.',
          );
        }
      }
      return;
    }
    final edit = await showDialog<StorefrontPreviewEditRequest>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StorefrontInAppPreviewDialog(
        previewUri: uri!,
        buildVersion: build.version,
        buildName: build.name,
        onEditRequest: (edit) => _createPreviewSiteEditJob(build, edit),
        onJobCompleted: _resolveSitePreviewEditCompletion,
      ),
    );
    if (edit == null || !mounted) return;
    await _startSiteCompilerRequest(
      _SiteCompilerRequest(
        edit.instruction,
        build.id,
        siteMode: build.singleProductId == null ? 'catalog' : 'single_product',
        selectedProductId: build.singleProductId,
        selectionContext: edit.selection.toJson(),
      ),
    );
  }

  Future<void> _publishSiteBuild(StorefrontSiteBuild build) async {
    final current = _publishedSiteBuild;
    final restoring = _isRestoreCandidate(build);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          restoring
              ? 'Restore version ${build.version}?'
              : 'Publish this generated site?',
        ),
        content: Text(
          current == null
              ? 'This exact generated website will become the customer storefront.'
              : 'Version ${current.version} will remain safely available in history. You can restore it at any time.',
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
            label: Text(restoring ? 'Restore version' : 'Publish site'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await StorefrontPageService.publishSiteBuild(build.id);
      await _refreshSiteBuilds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restoring
                  ? 'Version ${build.version} is now live.'
                  : 'Generated site version ${build.version} is now live.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _deleteSiteBuild(StorefrontSiteBuild build) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete draft version ${build.version}?'),
        content: const Text(
          'This removes only this unpublished draft. Your live storefront will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete draft'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await StorefrontPageService.deleteSiteBuild(build.id);
      await _refreshSiteBuilds();
    });
  }

  Future<void> _createPage() async {
    final request = await showDialog<_NewPageRequest>(
      context: context,
      builder: (context) => const _NewPageDialog(),
    );
    if (request == null) return;
    await _run(() async {
      final page = await StorefrontPageService.create({
        'branchId': _branchId,
        'storefrontType': widget.storefrontType,
        'pageType': request.type,
        'title': request.title,
        'slug': request.slug,
      });
      await _load();
      if (mounted) await _openPage(page);
    });
  }

  Future<void> _openPage(StorefrontPage page) async {
    final updated = await showDialog<StorefrontPage>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PageStudioDialog(page: page),
    );
    if (updated != null) await _load();
  }

  Future<void> _deletePage(StorefrontPage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text(
          '“${page.title}” and its public URL will be removed. Store products and themes are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete page'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await StorefrontPageService.delete(page.id);
      await _load();
    });
  }

  Future<void> _configureConnection() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StoreApiDialog(connection: _connection),
    );
    if (saved == true) await _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _studioHeader(colors),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _StudioStep(
                    icon: Icons.palette_outlined,
                    label: 'Design system',
                  ),
                  _StudioStep(
                    icon: Icons.view_quilt_outlined,
                    label: 'Pages & sections',
                  ),
                  _StudioStep(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Piki designer',
                  ),
                  _StudioStep(
                    icon: Icons.visibility_outlined,
                    label: 'Exact preview',
                  ),
                  _StudioStep(icon: Icons.public_rounded, label: 'Publish'),
                ],
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          MaterialBanner(
            content: Text(_error!),
            leading: const Icon(Icons.error_outline_rounded),
            actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else ...[
          _siteCompilerCard(colors),
          const SizedBox(height: 18),
          _sectionHeader(
            icon: Icons.web_stories_outlined,
            title: 'Website pages',
            detail:
                '${_pages.length} custom ${_pages.length == 1 ? 'page' : 'pages'} · shareable URLs · independent publishing',
          ),
          const SizedBox(height: 10),
          if (_pages.isEmpty)
            _emptyPages(colors)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth >= 620
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _pages
                      .map(
                        (page) => SizedBox(
                          width: width,
                          child: _pageCard(page, colors),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          const SizedBox(height: 18),
          _connectionCard(colors),
        ],
      ],
    );
  }

  Widget _studioHeader(ColorScheme colors) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.dashboard_customize_rounded, color: colors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Storefront Studio',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                'Build pages, navigation, and the connected catalogue in one workspace.',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (widget.onPreviewCurrentStore != null)
          OutlinedButton.icon(
            onPressed: _busy ? null : widget.onPreviewCurrentStore,
            icon: const Icon(Icons.web_asset_rounded),
            label: const Text('Preview store'),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _createPage,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New page'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [identity, const SizedBox(height: 16), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 18),
            actions,
          ],
        );
      },
    );
  }

  Widget _siteCompilerCard(ColorScheme colors) {
    final live = _publishedSiteBuild;
    final job = _siteJob;
    final isWorking = job?.isRunning == true;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: 0.025),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _siteCompilerHeader(colors, live, isWorking),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _CompilerCapability(
                icon: Icons.account_tree_outlined,
                label: 'Any page structure',
              ),
              _CompilerCapability(
                icon: Icons.devices_rounded,
                label: 'Responsive HTML & CSS',
              ),
              _CompilerCapability(
                icon: Icons.security_rounded,
                label: 'Sandboxed code',
              ),
              _CompilerCapability(
                icon: Icons.inventory_2_outlined,
                label: 'Live catalogue bindings',
              ),
              _CompilerCapability(
                icon: Icons.filter_1_rounded,
                label: 'One-product websites',
              ),
              _CompilerCapability(
                icon: Icons.history_rounded,
                label: 'Version history & rollback',
              ),
            ],
          ),
          if (job != null) ...[
            const SizedBox(height: 16),
            PikiActivityPanel(
              job: job,
              events: _siteEvents,
              title: job.payload?['selectionContext'] is Map
                  ? 'Piki is editing the selected element'
                  : 'Piki is coding your storefront',
            ),
            if (job.isFailed) ...[
              const SizedBox(height: 10),
              Text(
                'Your brief is saved. Recovery retries another AI response and can finish with a validated editable starter instead of remaining stuck.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _retrySiteCompilerJob,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Recover saved request'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          if (_siteBuilds.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Describe the website in your own words. Piki can create sidebars, editorial layouts, bold landing experiences, unusual navigation, and custom responsive compositions.',
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _sectionHeader(
              icon: Icons.layers_outlined,
              title: 'Generated site versions',
              detail:
                  '${_siteBuilds.length} secure ${_siteBuilds.length == 1 ? 'build' : 'builds'} · preview before publishing · one-click rollback',
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 840
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _siteBuilds.take(8).map((build) {
                    return SizedBox(
                      width: width,
                      child: _siteBuildCard(build, colors),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _siteCompilerHeader(
    ColorScheme colors,
    StorefrontSiteBuild? live,
    bool isWorking,
  ) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.code_rounded, color: colors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Piki Site Compiler',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (live != null)
                    Chip(
                      avatar: const Icon(Icons.public_rounded, size: 15),
                      label: Text('v${live.version} live'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Create a responsive site that stays connected to live products, pages, cart, and checkout.',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
    final action = FilledButton.icon(
      onPressed: _busy || isWorking ? null : () => _openSiteCompiler(),
      icon: Icon(
        live == null ? Icons.auto_awesome_rounded : Icons.draw_outlined,
      ),
      label: Text(live == null ? 'Code new site' : 'Refine with Piki'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 18),
            action,
          ],
        );
      },
    );
  }

  Widget _siteBuildCard(StorefrontSiteBuild build, ColorScheme colors) {
    final isRestore = _isRestoreCandidate(build);
    final shortHash = build.codeHash.length > 8
        ? build.codeHash.substring(0, 8)
        : build.codeHash;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: build.isPublished
              ? colors.primary.withValues(alpha: 0.5)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'v${build.version}',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                build.securityPassed
                    ? Icons.verified_user_outlined
                    : Icons.warning_amber_outlined,
                size: 17,
                color: build.securityPassed ? Colors.green : colors.error,
              ),
              const SizedBox(width: 5),
              Text(
                build.securityPassed ? 'Security passed' : 'Review required',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Chip(
                label: Text(
                  build.isPublished
                      ? 'Live'
                      : isRestore
                      ? 'History'
                      : 'Draft',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            build.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            build.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${build.singleProductId == null ? '${build.slots.length} live bindings' : 'One-product website'} · ${build.compilerVersion} · $shortHash',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _previewSiteBuild(build),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: Text(
                  Platform.isWindows ? 'Preview & edit' : 'Exact preview',
                ),
              ),
              if (!build.isPublished)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _publishSiteBuild(build),
                  icon: Icon(
                    isRestore ? Icons.history_rounded : Icons.publish_rounded,
                    size: 17,
                  ),
                  label: Text(isRestore ? 'Restore' : 'Publish'),
                ),
              IconButton.filledTonal(
                tooltip: 'Refine this version with Piki',
                onPressed: _busy ? null : () => _openSiteCompiler(build),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
              if (build.isDraft && !isRestore)
                IconButton(
                  tooltip: 'Delete draft',
                  onPressed: _busy ? null : () => _deleteSiteBuild(build),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            detail,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _emptyPages(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.note_add_outlined, size: 34, color: colors.primary),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add the pages customers expect',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Create About, FAQ, Contact, policy, and campaign landing pages.',
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: _createPage,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create first page'),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 18),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _pageCard(StorefrontPage page, ColorScheme colors) {
    return Card(
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _openPage(page),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _pageIcon(page.pageType),
                      size: 19,
                      color: colors.primary,
                    ),
                  ),
                  const Spacer(),
                  Chip(
                    avatar: Icon(
                      page.isPublished
                          ? Icons.public_rounded
                          : Icons.edit_note_rounded,
                      size: 15,
                    ),
                    label: Text(page.isPublished ? 'Live' : 'Draft'),
                    visualDensity: VisualDensity.compact,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') _deletePage(page);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete page'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                page.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '/page/${page.slug}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Text(
                '${page.sections.length} sections · ${page.showInNavigation ? 'In navigation' : 'Direct link only'}',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionCard(ColorScheme colors) {
    final connection = _connection;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      (connection?.isEnabled == true
                              ? Colors.green
                              : colors.primary)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: connection?.isEnabled == true
                      ? Colors.green
                      : colors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dynamic product API',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connection == null
                          ? 'Optionally show a product feed from another platform using encrypted server-side credentials.'
                          : connection.isEnabled
                          ? '${connection.name} is connected · ${connection.lastTestMessage ?? 'live product feed'}'
                          : '${connection.name} is saved but not enabled.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: _busy ? null : _configureConnection,
            icon: const Icon(Icons.settings_ethernet_rounded),
            label: Text(connection == null ? 'Connect API' : 'Manage'),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 18),
              action,
            ],
          );
        },
      ),
    );
  }

  IconData _pageIcon(String type) => switch (type) {
    'about' => Icons.auto_stories_outlined,
    'faq' => Icons.help_outline_rounded,
    'contact' => Icons.contact_support_outlined,
    'policy' => Icons.policy_outlined,
    'landing' => Icons.rocket_launch_outlined,
    _ => Icons.web_asset_outlined,
  };
}

class _CompilerCapability extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CompilerCapability({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SiteCompilerRequest {
  final String instruction;
  final String? parentBuildId;
  final String siteMode;
  final String? selectedProductId;
  final Map<String, dynamic>? selectionContext;

  const _SiteCompilerRequest(
    this.instruction,
    this.parentBuildId, {
    this.siteMode = 'catalog',
    this.selectedProductId,
    this.selectionContext,
  });
}

class _SiteCompilerDialog extends StatefulWidget {
  final StorefrontSiteBuild? baseBuild;
  final List<StorefrontBuilderItem> items;

  const _SiteCompilerDialog({required this.baseBuild, required this.items});

  @override
  State<_SiteCompilerDialog> createState() => _SiteCompilerDialogState();
}

class _SiteCompilerDialogState extends State<_SiteCompilerDialog> {
  late final TextEditingController _brief = TextEditingController();
  late bool _refineBase = widget.baseBuild != null;
  late String _siteMode = widget.baseBuild?.singleProductId == null
      ? 'catalog'
      : 'single_product';
  late String? _selectedProductId =
      widget.items.any((item) => item.id == widget.baseBuild?.singleProductId)
      ? widget.baseBuild?.singleProductId
      : null;

  static const _examples = [
    'Luxury editorial shop',
    'Categories in a left sidebar',
    'Bold mobile-first streetwear store',
    'Minimal catalogue with large photography',
    'One-product launch site',
  ];

  @override
  void dispose() {
    _brief.dispose();
    super.dispose();
  }

  void _addExample(String value) {
    setState(() {
      _brief.text = switch (value) {
        'Luxury editorial shop' =>
          'Code a luxury editorial storefront with a cinematic hero, refined serif headlines, quiet navigation, large image-first product cards, and generous spacing.',
        'Categories in a left sidebar' =>
          'Code a desktop catalogue with categories in a real sticky left sidebar, search and products on the right, then transform the sidebar into a horizontal category rail on mobile.',
        'Bold mobile-first streetwear store' =>
          'Create a bold mobile-first streetwear storefront with oversized typography, a compact sticky header, strong product imagery, high contrast, and an energetic editorial layout.',
        'One-product launch site' =>
          'Create a premium one-product launch website with a cinematic opening, an image-led product story, clear live pricing and options, strong mobile hierarchy, and a focused purchase journey.',
        _ =>
          'Create a minimal catalogue with large product photography, clean typography, subtle borders, a calm neutral palette, clear search, and an elegant responsive grid.',
      };
      _brief.selection = TextSelection.collapsed(offset: _brief.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.code_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Code a website with Piki',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Describe the structure and visual direction—not a preset name.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.baseBuild != null) ...[
                      SegmentedButton<bool>(
                        expandedInsets: EdgeInsets.zero,
                        segments: [
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.draw_outlined),
                            label: Text('Refine v${widget.baseBuild!.version}'),
                          ),
                          const ButtonSegment(
                            value: false,
                            icon: Icon(Icons.note_add_outlined),
                            label: Text('Start from blank'),
                          ),
                        ],
                        selected: {_refineBase},
                        onSelectionChanged: (selection) {
                          setState(() => _refineBase = selection.first);
                        },
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      'Website focus',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      expandedInsets: EdgeInsets.zero,
                      segments: const [
                        ButtonSegment(
                          value: 'catalog',
                          icon: Icon(Icons.grid_view_rounded),
                          label: Text('Full catalogue'),
                        ),
                        ButtonSegment(
                          value: 'single_product',
                          icon: Icon(Icons.filter_1_rounded),
                          label: Text('One product'),
                        ),
                      ],
                      selected: {_siteMode},
                      onSelectionChanged: (selection) {
                        setState(() => _siteMode = selection.first);
                      },
                    ),
                    if (_siteMode == 'single_product') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedProductId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Live product',
                          helperText:
                              'Price, images, stock, variants and checkout stay connected.',
                        ),
                        hint: Text(
                          widget.items.isEmpty
                              ? 'No live products are available'
                              : 'Choose the product for this website',
                        ),
                        items: widget.items.map((item) {
                          final detail = [
                            if (item.category?.isNotEmpty == true)
                              item.category!,
                            item.isConnected ? 'Connected API' : 'Piki POS',
                          ].join(' · ');
                          return DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              '${item.name}  —  $detail',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: widget.items.isEmpty
                            ? null
                            : (value) {
                                setState(() => _selectedProductId = value);
                              },
                      ),
                    ],
                    const SizedBox(height: 18),
                    TextField(
                      controller: _brief,
                      minLines: 6,
                      maxLines: 10,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Website brief',
                        alignLabelWithHint: true,
                        hintText:
                            'Example: Put categories in a sticky left sidebar. Use a warm editorial design, large image-first product cards, serif headings, compact navigation, and a responsive mobile category rail.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _examples.map((example) {
                        return ActionChip(
                          avatar: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 15,
                          ),
                          label: Text(example),
                          onPressed: () => _addExample(example),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.verified_user_outlined, size: 19),
                              SizedBox(width: 8),
                              Text(
                                'What Piki can safely code',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            'Piki can create and position the header, navigation, hero, sidebars, catalogue, search, promotional sections, cart action, WhatsApp action, footer, typography, spacing, colours, motion-ready states, grids, and mobile layouts.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Payments, customer forms, scripts, trackers, and API secrets stay outside generated code. Piki uses protected live bindings so the website remains dynamic and checkout remains trustworthy.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final status = Row(
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        size: 17,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Piki continues securely in the cloud if you close the app.',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  );
                  final submit = FilledButton.icon(
                    onPressed: () {
                      final instruction = _brief.text.trim();
                      if (instruction.length < 10) return;
                      if (_siteMode == 'single_product' &&
                          _selectedProductId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Choose the live product for this website.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(
                        context,
                        _SiteCompilerRequest(
                          instruction,
                          _refineBase ? widget.baseBuild?.id : null,
                          siteMode: _siteMode,
                          selectedProductId: _siteMode == 'single_product'
                              ? _selectedProductId
                              : null,
                        ),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _refineBase ? 'Create refined draft' : 'Code website',
                    ),
                  );
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      submit,
                    ],
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        status,
                        const SizedBox(height: 12),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: status),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioStep extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StudioStep({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _NewPageRequest {
  final String type;
  final String title;
  final String slug;

  const _NewPageRequest(this.type, this.title, this.slug);
}

class _NewPageDialog extends StatefulWidget {
  const _NewPageDialog();

  @override
  State<_NewPageDialog> createState() => _NewPageDialogState();
}

class _NewPageDialogState extends State<_NewPageDialog> {
  String _type = 'about';
  late final TextEditingController _title = TextEditingController(
    text: 'About us',
  );
  late final TextEditingController _slug = TextEditingController(
    text: 'about-us',
  );

  static const _templates = [
    (
      'about',
      'About',
      Icons.auto_stories_outlined,
      'Tell the real story behind the business.',
    ),
    (
      'faq',
      'FAQ',
      Icons.help_outline_rounded,
      'Answer common customer questions clearly.',
    ),
    (
      'contact',
      'Contact',
      Icons.contact_support_outlined,
      'Give customers a clear way to reach you.',
    ),
    (
      'policy',
      'Policy',
      Icons.policy_outlined,
      'Publish delivery, returns, or privacy information.',
    ),
    (
      'landing',
      'Landing page',
      Icons.rocket_launch_outlined,
      'Create a focused page for an offer or collection.',
    ),
    (
      'custom',
      'Blank page',
      Icons.web_asset_outlined,
      'Start with a clean, flexible page.',
    ),
  ];

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Create a website page'),
      content: SizedBox(
        width: (screen.width - 96).clamp(260.0, 650.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose a professional starting structure. Every section can be reordered, restyled, or rebuilt by Piki.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _templates.map((item) {
                  final selected = _type == item.$1;
                  return ChoiceChip(
                    selected: selected,
                    avatar: Icon(item.$3, size: 17),
                    label: Text(item.$2),
                    onSelected: (_) {
                      setState(() {
                        _type = item.$1;
                        _title.text = item.$2 == 'Blank page'
                            ? 'New page'
                            : item.$2;
                        _slug.text = _slugify(_title.text);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                _templates.firstWhere((item) => item.$1 == _type).$4,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Page title'),
                    onChanged: (value) => _slug.text = _slugify(value),
                  );
                  final slug = TextField(
                    controller: _slug,
                    decoration: const InputDecoration(
                      prefixText: '/page/',
                      labelText: 'Page URL',
                    ),
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      children: [title, const SizedBox(height: 12), slug],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      Expanded(child: slug),
                    ],
                  );
                },
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
          onPressed: () {
            final title = _title.text.trim();
            final slug = _slugify(_slug.text);
            if (title.isEmpty || slug.isEmpty) return;
            Navigator.pop(context, _NewPageRequest(_type, title, slug));
          },
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Create and edit'),
        ),
      ],
    );
  }

  String _slugify(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _PageStudioDialog extends StatefulWidget {
  final StorefrontPage page;

  const _PageStudioDialog({required this.page});

  @override
  State<_PageStudioDialog> createState() => _PageStudioDialogState();
}

class _PageStudioDialogState extends State<_PageStudioDialog> {
  late StorefrontPage _page = widget.page;
  late final TextEditingController _title = TextEditingController(
    text: _page.title,
  );
  late final TextEditingController _slug = TextEditingController(
    text: _page.slug,
  );
  late final TextEditingController _navigation = TextEditingController(
    text: _page.navigationLabel,
  );
  late final TextEditingController _seoTitle = TextEditingController(
    text: _page.seoTitle,
  );
  late final TextEditingController _seoDescription = TextEditingController(
    text: _page.seoDescription,
  );
  late final TextEditingController _pikiBrief = TextEditingController();
  late List<StorefrontThemeSection> _sections = [..._page.sections];
  bool _showInNavigation = true;
  bool _busy = false;
  PikiAiJob? _pikiJob;
  String? _error;
  int _panel = 0;

  @override
  void initState() {
    super.initState();
    _showInNavigation = _page.showInNavigation;
  }

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    _navigation.dispose();
    _seoTitle.dispose();
    _seoDescription.dispose();
    _pikiBrief.dispose();
    super.dispose();
  }

  Future<void> _editSections() async {
    final result = await showStorefrontSectionsEditor(
      context,
      sections: _sections,
      requireCatalog: false,
    );
    if (result == null || !mounted) return;
    setState(() {
      _sections = result.map(StorefrontThemeSection.fromJson).toList();
    });
  }

  Future<void> _save() async {
    await _run(() async {
      _page = await StorefrontPageService.update(_page.id, {
        'title': _title.text.trim(),
        'slug': _slug.text.trim(),
        'navigationLabel': _navigation.text.trim(),
        'showInNavigation': _showInNavigation,
        'seoTitle': _seoTitle.text.trim(),
        'seoDescription': _seoDescription.text.trim(),
        'sections': _sections.map((item) => item.toJson()).toList(),
      });
      _replaceFromPage(_page);
    });
  }

  Future<void> _designWithPiki() async {
    final instruction = _pikiBrief.text.trim();
    if (instruction.isEmpty) {
      setState(() => _error = 'Describe the page Piki should create.');
      return;
    }
    await _run(() async {
      await _saveDraftWithoutBusy();
      var job = await PikiAiJobService.createStorefrontPageJob(
        _page.id,
        instruction,
      );
      if (mounted) setState(() => _pikiJob = job);
      while (job.isRunning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await PikiAiJobService.getJob(job.id);
        if (mounted) setState(() => _pikiJob = job);
      }
      if (job.isFailed) {
        throw Exception(
          job.errorMessage ?? 'Piki could not finish the page design.',
        );
      }
      final value = job.result?['page'];
      if (value is! Map) {
        throw Exception('Piki finished without a saved page draft.');
      }
      _page = StorefrontPage.fromJson(Map<String, dynamic>.from(value));
      _replaceFromPage(_page);
      _pikiBrief.clear();
      _panel = 0;
      _pikiJob = null;
    });
  }

  Future<void> _saveDraftWithoutBusy() async {
    _page = await StorefrontPageService.update(_page.id, {
      'title': _title.text.trim(),
      'slug': _slug.text.trim(),
      'navigationLabel': _navigation.text.trim(),
      'showInNavigation': _showInNavigation,
      'seoTitle': _seoTitle.text.trim(),
      'seoDescription': _seoDescription.text.trim(),
      'sections': _sections.map((item) => item.toJson()).toList(),
    });
  }

  void _replaceFromPage(StorefrontPage page) {
    setState(() {
      _page = page;
      _title.text = page.title;
      _slug.text = page.slug;
      _navigation.text = page.navigationLabel;
      _seoTitle.text = page.seoTitle;
      _seoDescription.text = page.seoDescription;
      _showInNavigation = page.showInNavigation;
      _sections = [...page.sections];
    });
  }

  Future<void> _preview() async {
    await _run(() async {
      await _saveDraftWithoutBusy();
      final uri = await StorefrontPageService.previewUrl(_page.id);
      if (Platform.isWindows && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StorefrontInAppPreviewDialog(
            previewUri: uri,
            buildName: _page.title,
            enablePointAndEdit: false,
          ),
        );
        return;
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open the exact website preview.');
      }
    });
  }

  Future<void> _togglePublish() async {
    await _run(() async {
      await _saveDraftWithoutBusy();
      _page = _page.isPublished
          ? await StorefrontPageService.unpublish(_page.id)
          : await StorefrontPageService.publish(_page.id);
      _replaceFromPage(_page);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 10 : 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 780),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.web_stories_outlined,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _page.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              '/page/${_page.slug} · ${_page.isPublished ? 'Live' : 'Draft'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _preview,
                          icon: const Icon(Icons.visibility_outlined),
                          label: Text(
                            Platform.isWindows
                                ? 'Preview in app'
                                : 'Exact preview',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _busy ? null : _togglePublish,
                          icon: Icon(
                            _page.isPublished
                                ? Icons.public_off_outlined
                                : Icons.publish_rounded,
                          ),
                          label: Text(
                            _page.isPublished ? 'Unpublish' : 'Publish',
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IconButton(
                        tooltip: 'Close page studio',
                        onPressed: _busy
                            ? null
                            : () => Navigator.pop(context, _page),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (compact) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _preview,
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Preview'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _togglePublish,
                            icon: Icon(
                              _page.isPublished
                                  ? Icons.public_off_outlined
                                  : Icons.publish_rounded,
                            ),
                            label: Text(
                              _page.isPublished ? 'Unpublish' : 'Publish',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: compact
                  ? Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLowest,
                            border: Border(
                              bottom: BorderSide(color: colors.outlineVariant),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _studioCompactNav(
                                  0,
                                  Icons.view_quilt_outlined,
                                  'Layout',
                                ),
                              ),
                              Expanded(
                                child: _studioCompactNav(
                                  1,
                                  Icons.tune_rounded,
                                  'Settings',
                                ),
                              ),
                              Expanded(
                                child: _studioCompactNav(
                                  2,
                                  Icons.auto_awesome_rounded,
                                  'Piki',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _panelBody(colors)),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          width: 210,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLowest,
                            border: Border(
                              right: BorderSide(color: colors.outlineVariant),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _studioNav(
                                0,
                                Icons.view_quilt_outlined,
                                'Page layout',
                                '${_sections.length} sections',
                              ),
                              _studioNav(
                                1,
                                Icons.tune_rounded,
                                'Page settings',
                                'URL, navigation, SEO',
                              ),
                              _studioNav(
                                2,
                                Icons.auto_awesome_rounded,
                                'Design with Piki',
                                'Describe any page',
                              ),
                              const Spacer(),
                              Text(
                                'Changes remain a draft until you publish. Preview uses the exact customer website.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _panelBody(colors)),
                      ],
                    ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                color: colors.errorContainer,
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: Row(
                children: [
                  if (_busy)
                    const Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Saving…'),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, _page),
                    child: const Text('Done'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.cloud_done_outlined),
                    label: Text(compact ? 'Save' : 'Save draft'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studioNav(int index, IconData icon, String title, String subtitle) {
    final selected = _panel == index;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _panel = index),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected ? colors.primary.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studioCompactNav(int index, IconData icon, String title) {
    final selected = _panel == index;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _panel = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? colors.onPrimary : colors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelBody(ColorScheme colors) {
    if (_panel == 1) return _settingsPanel();
    if (_panel == 2) return _pikiPanel(colors);
    return _layoutPanel(colors);
  }

  Widget _layoutPanel(ColorScheme colors) {
    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customer journey',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Sections render in this exact order on the website.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              );
              final action = FilledButton.tonalIcon(
                onPressed: _busy ? null : _editSections,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit sections'),
              );
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [copy, const SizedBox(height: 12), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 16),
                  action,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: ReorderableListView.builder(
                itemCount: _sections.length,
                onReorder: (oldIndex, newIndex) => setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _sections.removeAt(oldIndex);
                  _sections.insert(newIndex, item);
                }),
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  return Card(
                    key: ValueKey(section.id),
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.drag_indicator_rounded),
                      title: Text(
                        section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${section.type} · ${section.data['width'] ?? 'contained'} · ${section.data['spacing'] ?? 'comfortable'}',
                      ),
                      trailing: Icon(
                        section.enabled
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsPanel() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page settings',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final title = TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Page title'),
              );
              final slug = TextField(
                controller: _slug,
                decoration: const InputDecoration(
                  prefixText: '/page/',
                  labelText: 'URL',
                ),
              );
              if (constraints.maxWidth < 480) {
                return Column(
                  children: [title, const SizedBox(height: 12), slug],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  Expanded(child: slug),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _navigation,
            decoration: const InputDecoration(labelText: 'Navigation label'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showInNavigation,
            title: const Text('Show in website navigation'),
            subtitle: const Text(
              'Customers can still open a hidden page using its direct URL.',
            ),
            onChanged: (value) => setState(() => _showInNavigation = value),
          ),
          const Divider(height: 32),
          Text(
            'Search & sharing',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seoTitle,
            maxLength: 70,
            decoration: const InputDecoration(labelText: 'SEO title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seoDescription,
            minLines: 3,
            maxLines: 5,
            maxLength: 180,
            decoration: const InputDecoration(
              labelText: 'SEO description',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pikiPanel(ColorScheme colors) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Piki Page Designer',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Piki writes and arranges a safe draft; you remain in control of preview and publishing.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pikiBrief,
            minLines: 7,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Describe the page you want',
              hintText:
                  'Example: Create a premium About page with a large story hero, our values in three columns, a photo gallery, and a WhatsApp contact section. Keep the tone warm and credible.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                      'Make it premium and editorial',
                      'Build a clear FAQ from verified information',
                      'Create a conversion-focused landing page',
                      'Use a spacious image-led layout',
                    ]
                    .map(
                      (prompt) => ActionChip(
                        label: Text(prompt),
                        onPressed: () => _pikiBrief.text = prompt,
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 18),
          if (_pikiJob != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _pikiJob!.currentStep ?? 'Piki is designing the page',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('${_pikiJob!.progress}%'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _pikiJob!.progress / 100),
                  const SizedBox(height: 8),
                  Text(
                    'This work is saved in Piki Cloud and continues if you close the app.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _designWithPiki,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Design this page'),
          ),
        ],
      ),
    );
  }
}

class _StoreApiDialog extends StatefulWidget {
  final StorefrontConnection? connection;

  const _StoreApiDialog({required this.connection});

  @override
  State<_StoreApiDialog> createState() => _StoreApiDialogState();
}

class _StoreApiDialogState extends State<_StoreApiDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.connection?.name ?? 'Store product API',
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.connection?.endpointUrl ?? '',
  );
  late final TextEditingController _secret = TextEditingController();
  late final TextEditingController _header = TextEditingController(
    text: widget.connection?.apiKeyHeader ?? 'X-API-Key',
  );
  late final TextEditingController _dataPath = TextEditingController(
    text: widget.connection?.dataPath ?? 'products',
  );
  late final TextEditingController _idPath = TextEditingController(
    text: widget.connection?.fieldMappings['id'] ?? 'id',
  );
  late final TextEditingController _namePath = TextEditingController(
    text: widget.connection?.fieldMappings['name'] ?? 'name',
  );
  late final TextEditingController _pricePath = TextEditingController(
    text: widget.connection?.fieldMappings['price'] ?? 'price',
  );
  late final TextEditingController _stockPath = TextEditingController(
    text: widget.connection?.fieldMappings['stock'] ?? 'stock',
  );
  late final TextEditingController _imagePath = TextEditingController(
    text: widget.connection?.fieldMappings['imageUrl'] ?? 'image_url',
  );
  late final TextEditingController _checkoutPath = TextEditingController(
    text: widget.connection?.fieldMappings['checkoutUrl'] ?? 'url',
  );
  late String _authType = widget.connection?.authType ?? 'none';
  late bool _enabled = widget.connection?.isEnabled ?? false;
  bool _busy = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _secret.dispose();
    _header.dispose();
    _dataPath.dispose();
    _idPath.dispose();
    _namePath.dispose();
    _pricePath.dispose();
    _stockPath.dispose();
    _imagePath.dispose();
    _checkoutPath.dispose();
    super.dispose();
  }

  Future<void> _save({bool test = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await StorefrontPageService.saveConnection({
        'branchId': 'main_branch',
        'name': _name.text.trim(),
        'endpointUrl': _endpoint.text.trim(),
        'authType': _authType,
        'apiKeyHeader': _header.text.trim(),
        'dataPath': _dataPath.text.trim(),
        'fieldMappings': {
          'id': _idPath.text.trim(),
          'name': _namePath.text.trim(),
          'price': _pricePath.text.trim(),
          'stock': _stockPath.text.trim(),
          'imageUrl': _imagePath.text.trim(),
          'checkoutUrl': _checkoutPath.text.trim(),
        },
        'isEnabled': _enabled,
        if (_secret.text.trim().isNotEmpty) 'secret': _secret.text.trim(),
      });
      if (test) {
        final result = await StorefrontPageService.testConnection();
        if (mounted) setState(() => _message = result);
      } else if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) setState(() => _message = AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget responsiveFields(List<Widget> fields) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                for (var index = 0; index < fields.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  fields[index],
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                if (index > 0) const SizedBox(width: 10),
                Expanded(child: fields[index]),
              ],
            ],
          );
        },
      );
    }

    final screen = MediaQuery.sizeOf(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Dynamic product API'),
      content: SizedBox(
        width: (screen.width - 96).clamp(260.0, 620.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Connect a public HTTPS JSON product feed. Credentials are encrypted on the server and are never sent to Piki or the storefront.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Connection name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endpoint,
                decoration: const InputDecoration(
                  labelText: 'HTTPS product endpoint',
                  hintText: 'https://store.example.com/api/products',
                ),
              ),
              const SizedBox(height: 12),
              responsiveFields([
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _authType,
                  decoration: const InputDecoration(
                    labelText: 'Authentication',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('No authentication'),
                    ),
                    DropdownMenuItem(
                      value: 'bearer',
                      child: Text('Bearer token'),
                    ),
                    DropdownMenuItem(
                      value: 'apiKey',
                      child: Text('API key header'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _authType = value ?? _authType),
                ),
                if (_authType == 'apiKey') ...[
                  TextField(
                    controller: _header,
                    decoration: const InputDecoration(labelText: 'Header name'),
                  ),
                ],
              ]),
              if (_authType != 'none') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _secret,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: widget.connection?.hasSecret == true
                        ? 'Credential (leave blank to keep saved)'
                        : 'Credential',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _dataPath,
                decoration: const InputDecoration(
                  labelText: 'Product list path',
                  hintText: 'products',
                  helperText:
                      'Dot notation is supported, for example data.products.',
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('Field mapping'),
                subtitle: const Text(
                  'Match your API field names to storefront product fields.',
                ),
                children: [
                  responsiveFields([
                    TextField(
                      controller: _idPath,
                      decoration: const InputDecoration(
                        labelText: 'Product ID path',
                      ),
                    ),
                    TextField(
                      controller: _namePath,
                      decoration: const InputDecoration(labelText: 'Name path'),
                    ),
                    TextField(
                      controller: _pricePath,
                      decoration: const InputDecoration(
                        labelText: 'Price path',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  responsiveFields([
                    TextField(
                      controller: _stockPath,
                      decoration: const InputDecoration(
                        labelText: 'Stock path',
                      ),
                    ),
                    TextField(
                      controller: _imagePath,
                      decoration: const InputDecoration(
                        labelText: 'Image URL path',
                      ),
                    ),
                    TextField(
                      controller: _checkoutPath,
                      decoration: const InputDecoration(
                        labelText: 'Product URL path',
                      ),
                    ),
                  ]),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                title: const Text('Show this feed on the storefront'),
                subtitle: const Text(
                  'External items use their secure product URL for checkout; native Piki products continue using Piki checkout.',
                ),
                onChanged: (value) => setState(() => _enabled = value),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _save(test: true),
          icon: const Icon(Icons.cable_rounded),
          label: const Text('Save & test'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save connection'),
        ),
      ],
    );
  }
}
