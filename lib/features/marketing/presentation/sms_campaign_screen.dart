import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../customers/data/customer_group_repository.dart';
import '../data/sms_campaign_repository.dart';

class SmsCampaignScreen extends StatefulWidget {
  const SmsCampaignScreen({super.key});

  @override
  State<SmsCampaignScreen> createState() => _SmsCampaignScreenState();
}

class _SmsCampaignScreenState extends State<SmsCampaignScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _segment = 'all';
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _campaignsFuture;
  late Future<List<Map<String, dynamic>>> _recipientsFuture;

  static const _segments = <String, String>{
    'all': 'All Customers',
    'debtors': 'Kopesha Debtors',
    'loyalty': 'Loyalty Customers',
    'inactive': 'Inactive 60 Days',
  };

  @override
  void initState() {
    super.initState();
    _nameController.text =
        'SMS Campaign ${DateTime.now().toString().substring(0, 10)}';
    _messageController.text = 'Hi {name}, we have an offer for you today.';
    _campaignsFuture = SmsCampaignRepository.getAll();
    _recipientsFuture = SmsCampaignRepository.previewRecipients(_segment);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _refreshCampaigns() {
    setState(() => _campaignsFuture = SmsCampaignRepository.getAll());
  }

  void _refreshRecipients() {
    setState(
      () =>
          _recipientsFuture = SmsCampaignRepository.previewRecipients(_segment),
    );
  }

  Future<void> _sendCampaign() async {
    setState(() => _busy = true);
    try {
      final campaignId = await SmsCampaignRepository.createDraft(
        name: _nameController.text,
        segment: _segment,
        message: _messageController.text,
      );
      final result = await SmsCampaignRepository.sendCampaign(campaignId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent ${result['sent'] ?? 0}, failed ${result['failed'] ?? 0}.',
          ),
          backgroundColor: (result['failed'] ?? 0) > 0
              ? AppColors.warning
              : AppColors.success,
        ),
      );
      _refreshCampaigns();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 980;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Campaigns'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshCampaigns,
            icon: const Icon(Icons.refresh_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _busy ? null : _sendCampaign,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send'),
            ),
          ),
        ],
      ),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 420, child: _buildComposer()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildHistory()),
              ],
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [_buildComposer(), const Divider(), _buildHistory()],
            ),
    );
  }

  Widget _buildComposer() {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Campaign name',
            prefixIcon: Icon(Icons.campaign_rounded),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: CustomerGroupRepository.getAll(),
          builder: (context, snapshot) {
            final groups = snapshot.data ?? const <Map<String, dynamic>>[];
            return DropdownButtonFormField<String>(
              initialValue: _segment,
              decoration: const InputDecoration(
                labelText: 'Segment',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
              items: [
                ..._segments.entries.map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                ),
                ...groups.map(
                  (group) => DropdownMenuItem(
                    value: 'group:${group['id']}',
                    child: Text('Group: ${group['name']}'),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _segment = value);
                _refreshRecipients();
              },
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _messageController,
          minLines: 5,
          maxLines: 8,
          maxLength: 320,
          decoration: const InputDecoration(
            labelText: 'Message',
            prefixIcon: Icon(Icons.sms_rounded),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _recipientsFuture,
          builder: (context, snapshot) {
            final recipients = snapshot.data ?? const <Map<String, dynamic>>[];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.phone_android_rounded),
                ),
                title: Text('${recipients.length} recipients'),
                subtitle: Text(
                  _segments[_segment] ??
                      (_segment.startsWith('group:')
                          ? 'Customer group'
                          : 'All Customers'),
                ),
                trailing: IconButton(
                  tooltip: 'Refresh recipients',
                  onPressed: _refreshRecipients,
                  icon: const Icon(Icons.sync_rounded),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _campaignsFuture,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return const Center(child: Text('No campaigns yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final sent = (row['sent_count'] as num? ?? 0).toInt();
            final failed = (row['failed_count'] as num? ?? 0).toInt();
            final recipients = (row['recipient_count'] as num? ?? 0).toInt();
            final status = row['status'] as String? ?? 'draft';
            final color = status == 'sent'
                ? AppColors.success
                : status == 'failed'
                ? AppColors.error
                : AppColors.warning;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(Icons.campaign_rounded, color: color),
                ),
                title: Text(row['name'] as String? ?? 'Campaign'),
                subtitle: Text(
                  '${_segments[row['segment']] ?? row['segment']} - $sent sent, $failed failed, $recipients recipients',
                ),
                trailing: Text(status),
              ),
            );
          },
        );
      },
    );
  }
}
