import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/piki_ai_job_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/piki_activity_panel.dart';
import '../../products/data/product_repository.dart';
import '../../services/data/service_repository.dart';

class StorefrontMarketingSection extends StatefulWidget {
  final String storefrontType;

  const StorefrontMarketingSection({super.key, this.storefrontType = 'retail'});

  @override
  State<StorefrontMarketingSection> createState() =>
      _StorefrontMarketingSectionState();
}

class _StorefrontMarketingSectionState
    extends State<StorefrontMarketingSection> {
  final _brief = TextEditingController();
  List<Map<String, dynamic>> _products = const [];
  final Set<String> _selectedProductIds = {};
  PikiAiJob? _job;
  List<PikiAiJobEvent> _events = const [];
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _brief.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _loadMarketingItems(),
        PikiAiJobService.listMarketingContentJobs(),
      ]);
      final products = (results[0] as List<Map<String, dynamic>>)
          .where(
            (product) =>
                product['deleted_at'] == null &&
                (product['show_online'] == null || product['show_online'] != 0),
          )
          .toList();
      final jobs = results[1] as List<PikiAiJob>;
      if (!mounted) return;
      setState(() {
        _products = products;
        _job = jobs.firstOrNull;
        if (_selectedProductIds.isEmpty) {
          _selectedProductIds.addAll(
            products
                .where((product) => product['is_featured'] == 1)
                .take(8)
                .map((product) => product['id'].toString()),
          );
        }
      });
      if (_job != null) {
        _events = await PikiAiJobService.getEvents(_job!.id);
        if (mounted) setState(() {});
      }
      _syncPolling();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadMarketingItems() async {
    if (widget.storefrontType != 'services') return ProductRepository.getAll();
    final services = await ServiceRepository.getServices(activeOnly: true);
    return services
        .map(
          (service) => <String, dynamic>{
            ...service,
            'id': 'service:${service['id']}',
            'show_online': 1,
            'is_featured': 0,
          },
        )
        .toList();
  }

  void _syncPolling() {
    _timer?.cancel();
    if (_job?.isRunning != true) return;
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshJob()),
    );
  }

  Future<void> _refreshJob() async {
    final current = _job;
    if (current == null) return;
    try {
      final results = await Future.wait([
        PikiAiJobService.getJob(current.id),
        PikiAiJobService.getEvents(current.id),
      ]);
      if (!mounted) return;
      setState(() {
        _job = results[0] as PikiAiJob;
        _events = results[1] as List<PikiAiJobEvent>;
      });
      if (_job?.isRunning != true) _timer?.cancel();
    } catch (_) {
      // The saved cloud job keeps running if a refresh request is interrupted.
    }
  }

  Future<void> _generate() async {
    final instruction = _brief.text.trim();
    if (instruction.length < 5 || _busy || _job?.isRunning == true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await PikiAiJobService.createMarketingContentJob(
        instruction,
        storefrontType: widget.storefrontType,
        productIds: _selectedProductIds.toList(),
      );
      if (!mounted) return;
      setState(() {
        _job = job;
        _events = const [];
      });
      _syncPolling();
      unawaited(_refreshJob());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Piki is writing in the cloud. It continues if you close the app.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    final job = _job;
    if (job == null || !job.isFailed) return;
    setState(() => _busy = true);
    try {
      final retried = await PikiAiJobService.retryJob(job.id);
      if (!mounted) return;
      setState(() {
        _job = retried;
        _events = const [];
      });
      _syncPolling();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Future<void> _openWhatsApp(String message) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open WhatsApp.');
    }
  }

  Future<void> _applyProductDescription(
    String productId,
    String productName,
    String description,
  ) async {
    if (productId.isEmpty || description.trim().isEmpty) return;
    final product = _products
        .where((item) => item['id']?.toString() == productId)
        .firstOrNull;
    final existing = product?['description']?.toString().trim() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing.isEmpty ? 'Apply description?' : 'Replace description?',
        ),
        content: Text(
          existing.isEmpty
              ? 'Save this reviewed draft as the online description for $productName?'
              : '$productName already has a description. Replace it with this reviewed Piki draft?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(existing.isEmpty ? 'Apply' : 'Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProductRepository.update(productId, {
      'description': description.trim(),
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });
    if (!mounted) return;
    setState(() {
      final index = _products.indexWhere(
        (item) => item['id']?.toString() == productId,
      );
      if (index >= 0) {
        _products[index] = {
          ..._products[index],
          'description': description.trim(),
        };
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$productName description updated')));
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Piki Marketing Studio',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Generate one fact-checked pack with social captions, WhatsApp copy, and product descriptions.',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _brief,
                        minLines: 3,
                        maxLines: 6,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Campaign brief',
                          hintText:
                              'Example: Introduce our featured products to busy Nairobi customers in a warm, direct tone. Do not mention discounts.',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          _selectedProductIds.isEmpty
                              ? 'Use the strongest online products automatically'
                              : '${_selectedProductIds.length} products selected',
                        ),
                        subtitle: const Text(
                          'Choose products when the campaign should be focused.',
                        ),
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 250),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _products.length,
                              itemBuilder: (context, index) {
                                final product = _products[index];
                                final id = product['id']?.toString() ?? '';
                                return CheckboxListTile(
                                  dense: true,
                                  value: _selectedProductIds.contains(id),
                                  title: Text(
                                    product['name']?.toString() ?? 'Product',
                                  ),
                                  onChanged: (value) => setState(() {
                                    if (value == true &&
                                        _selectedProductIds.length < 20) {
                                      _selectedProductIds.add(id);
                                    } else {
                                      _selectedProductIds.remove(id);
                                    }
                                  }),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed:
                              _brief.text.trim().length < 5 ||
                                  _busy ||
                                  _job?.isRunning == true
                              ? null
                              : _generate,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: const Text('Generate marketing pack'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _MarketingError(message: _error!),
              ],
              if (_loading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ] else if (_job != null) ...[
                const SizedBox(height: 16),
                PikiActivityPanel(
                  job: _job!,
                  events: _events,
                  title: _job!.isRunning
                      ? 'Piki is preparing the marketing pack'
                      : _job!.status == 'completed'
                      ? 'Marketing pack ready'
                      : 'Piki could not finish the marketing pack',
                ),
                if (_job!.isRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This cloud task continues when you leave this page or close the app.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                if (_job!.isFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ),
                  ),
                if (_job!.status == 'completed') ...[
                  const SizedBox(height: 16),
                  _buildResults(_job!.result ?? const {}),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(Map<String, dynamic> result) {
    final captions = (result['socialCaptions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final descriptions = (result['productDescriptions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final whatsapp = Map<String, dynamic>.from(
      result['whatsapp'] as Map? ?? const {},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          result['campaignName']?.toString() ?? 'Marketing pack',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (result['summary'] != null) ...[
          const SizedBox(height: 4),
          Text(result['summary'].toString()),
        ],
        const SizedBox(height: 14),
        if (whatsapp['message']?.toString().trim().isNotEmpty == true)
          _ContentCard(
            icon: Icons.chat_outlined,
            title: whatsapp['headline']?.toString() ?? 'WhatsApp campaign',
            content: [
              whatsapp['message']?.toString() ?? '',
              whatsapp['cta']?.toString() ?? '',
            ].where((item) => item.isNotEmpty).join('\n\n'),
            primaryLabel: 'Open WhatsApp',
            onPrimary: () => _openWhatsApp(whatsapp['message'].toString()),
            onCopy: () =>
                _copy(whatsapp['message'].toString(), 'WhatsApp message'),
          ),
        for (final caption in captions) ...[
          const SizedBox(height: 10),
          _ContentCard(
            icon: Icons.tag_rounded,
            title: '${caption['channel'] ?? 'Social'} caption',
            content: [
              caption['caption']?.toString() ?? '',
              ((caption['hashtags'] as List?) ?? const [])
                  .map((tag) => '#$tag')
                  .join(' '),
            ].where((item) => item.isNotEmpty).join('\n\n'),
            onCopy: () => _copy(
              [
                caption['caption']?.toString() ?? '',
                ((caption['hashtags'] as List?) ?? const [])
                    .map((tag) => '#$tag')
                    .join(' '),
              ].where((item) => item.isNotEmpty).join('\n\n'),
              'Social caption',
            ),
          ),
        ],
        if (descriptions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Product description drafts',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final description in descriptions) ...[
            _ContentCard(
              icon: Icons.inventory_2_outlined,
              title: description['name']?.toString() ?? 'Product',
              content: description['description']?.toString() ?? '',
              onCopy: () => _copy(
                description['description']?.toString() ?? '',
                'Product description',
              ),
              onPrimary: widget.storefrontType == 'services'
                  ? null
                  : () => _applyProductDescription(
                      description['productId']?.toString() ?? '',
                      description['name']?.toString() ?? 'Product',
                      description['description']?.toString() ?? '',
                    ),
              primaryLabel: widget.storefrontType == 'services'
                  ? null
                  : 'Apply to product',
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  String _message(Object error) => AppErrorMessage.from(
    error,
    fallback: 'Piki could not prepare the marketing pack. Try again.',
  );
}

class _ContentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final VoidCallback onCopy;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  const _ContentCard({
    required this.icon,
    required this.title,
    required this.content,
    required this.onCopy,
    this.primaryLabel,
    this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(content, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy'),
                ),
                if (onPrimary != null)
                  FilledButton.icon(
                    onPressed: onPrimary,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(primaryLabel ?? 'Open'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketingError extends StatelessWidget {
  final String message;

  const _MarketingError({required this.message});

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
        ],
      ),
    );
  }
}
