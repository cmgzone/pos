import 'package:flutter/material.dart';

import '../../../core/services/messaging_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';

class CommunicationSettingsSection extends StatefulWidget {
  const CommunicationSettingsSection({super.key});

  @override
  State<CommunicationSettingsSection> createState() =>
      _CommunicationSettingsSectionState();
}

class _CommunicationSettingsSectionState
    extends State<CommunicationSettingsSection> {
  final _whatsappController = TextEditingController();
  final _senderController = TextEditingController();
  bool _allowApiSend = true;
  bool _loading = true;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _whatsappController.dispose();
    _senderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final settings = await MessagingService.fetchSettings();
      if (!mounted) return;
      setState(() {
        _whatsappController.text = settings['whatsappNumber']?.toString() ?? '';
        _senderController.text = settings['smsSenderId']?.toString() ?? '';
        _allowApiSend = settings['allowApiSend'] != false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = AppErrorMessage.from(
          error,
          fallback: AppErrorMessage.loadFailed,
        );
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await MessagingService.saveSettings(
        whatsappNumber: _whatsappController.text,
        smsSenderId: _senderController.text,
        allowApiSend: _allowApiSend,
      );
      if (!mounted) return;
      setState(() => _message = 'Messaging settings saved');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _message = AppErrorMessage.from(
          error,
          fallback: AppErrorMessage.saveFailed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Business WhatsApp number',
                    prefixIcon: Icon(Icons.chat_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _senderController,
                  decoration: const InputDecoration(
                    labelText: 'SMS sender ID',
                    prefixIcon: Icon(Icons.sms_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allowApiSend,
            onChanged: (value) => setState(() => _allowApiSend = value),
            title: const Text('Allow API sending'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save Messaging'),
            ),
          ),
        ],
      ),
    );
  }
}
