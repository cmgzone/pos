import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../agent/data/piki_cloud_service.dart';

class PikiCloudSettingsSection extends StatefulWidget {
  const PikiCloudSettingsSection({super.key});

  @override
  State<PikiCloudSettingsSection> createState() =>
      _PikiCloudSettingsSectionState();
}

class _PikiCloudSettingsSectionState extends State<PikiCloudSettingsSection> {
  final _emailController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String _minimumSeverity = 'high';
  int _cooldownMinutes = 360;
  bool _emailConfigured = false;
  DateTime? _lastDeliveryAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await PikiCloudService.fetchSettings();
      if (!mounted) return;
      setState(() {
        _enabled = settings.enabled;
        _emailController.text = settings.notificationEmail;
        _minimumSeverity = settings.minimumSeverity;
        _cooldownMinutes = settings.cooldownMinutes;
        _emailConfigured = settings.emailConfigured;
        _lastDeliveryAt = settings.lastDeliveryAt;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppErrorMessage.from(
          error,
          fallback: 'Could not load Piki Cloud settings.',
        );
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final settings = await PikiCloudService.saveSettings(
        enabled: _enabled,
        notificationEmail: _emailController.text,
        minimumSeverity: _minimumSeverity,
        cooldownMinutes: _cooldownMinutes,
      );
      if (!mounted) return;
      setState(() {
        _enabled = settings.enabled;
        _emailController.text = settings.notificationEmail;
        _minimumSeverity = settings.minimumSeverity;
        _cooldownMinutes = settings.cooldownMinutes;
        _emailConfigured = settings.emailConfigured;
        _lastDeliveryAt = settings.lastDeliveryAt;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.enabled
                ? 'Piki Cloud is on. Alerts will be emailed while this app is closed.'
                : 'Piki Cloud alerts are off.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback: 'Could not save Piki Cloud settings.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return _buildSurface(
        context,
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return _buildSurface(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cloud_queue_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Piki Cloud',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Server-side business monitoring and email alerts.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Piki checks the synced cloud data about every 15 minutes. It only emails alerts after you turn this on, and it never changes your business data.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: _emailConfigured
                ? (value) => setState(() => _enabled = value)
                : null,
            title: const Text('Email Piki Cloud alerts'),
            subtitle: Text(
              _emailConfigured
                  ? 'Runs even when your phone or desktop app is closed.'
                  : 'Email delivery is not configured on the cloud server yet.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Alert email address',
              hintText: 'owner@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('piki-cloud-severity-$_minimumSeverity'),
            initialValue: _minimumSeverity,
            decoration: const InputDecoration(
              labelText: 'Alert level',
              prefixIcon: Icon(Icons.priority_high_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'high', child: Text('High only')),
              DropdownMenuItem(value: 'medium', child: Text('Medium and high')),
              DropdownMenuItem(value: 'info', child: Text('All Piki alerts')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _minimumSeverity = value);
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            key: ValueKey('piki-cloud-cooldown-$_cooldownMinutes'),
            initialValue: _cooldownOptions.contains(_cooldownMinutes)
                ? _cooldownMinutes
                : 360,
            decoration: const InputDecoration(
              labelText: 'Repeat reminder after',
              prefixIcon: Icon(Icons.schedule_outlined),
            ),
            items: _cooldownOptions
                .map(
                  (minutes) => DropdownMenuItem(
                    value: minutes,
                    child: Text(_cooldownLabel(minutes)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _cooldownMinutes = value);
            },
          ),
          if (_lastDeliveryAt != null) ...[
            const SizedBox(height: 14),
            Text(
              'Last cloud alert: ${DateFormat('MMM d, yyyy · HH:mm').format(_lastDeliveryAt!.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_done_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Piki Cloud'),
          ),
        ],
      ),
    );
  }

  Widget _buildSurface(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

const _cooldownOptions = <int>[60, 180, 360, 720, 1440];

String _cooldownLabel(int minutes) {
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60;
  return hours == 1 ? '1 hour' : '$hours hours';
}
