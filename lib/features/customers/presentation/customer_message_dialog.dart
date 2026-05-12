import 'package:flutter/material.dart';

import '../../../core/services/messaging_service.dart';
import '../../../core/theme/app_colors.dart';

class CustomerMessageDialog extends StatefulWidget {
  final String customerName;
  final String phoneNumber;
  final String initialMessage;
  final Map<String, dynamic>? metadata;

  const CustomerMessageDialog({
    super.key,
    required this.customerName,
    required this.phoneNumber,
    required this.initialMessage,
    this.metadata,
  });

  static Future<void> show(
    BuildContext context, {
    required String customerName,
    required String phoneNumber,
    required String initialMessage,
    Map<String, dynamic>? metadata,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CustomerMessageDialog(
        customerName: customerName,
        phoneNumber: phoneNumber,
        initialMessage: initialMessage,
        metadata: metadata,
      ),
    );
  }

  @override
  State<CustomerMessageDialog> createState() => _CustomerMessageDialogState();
}

class _CustomerMessageDialogState extends State<CustomerMessageDialog> {
  late final TextEditingController _phoneController;
  late final TextEditingController _messageController;
  CustomerMessageChannel _channel = CustomerMessageChannel.whatsapp;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.phoneNumber);
    _messageController = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send({required bool api}) async {
    setState(() => _sending = true);
    try {
      if (api) {
        await MessagingService.sendApi(
          channel: _channel,
          phoneNumber: _phoneController.text,
          message: _messageController.text,
          metadata: widget.metadata,
        );
      } else {
        await MessagingService.openManual(
          channel: _channel,
          phoneNumber: _phoneController.text,
          message: _messageController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(api ? 'Message sent' : 'Message opened')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Message ${widget.customerName}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<CustomerMessageChannel>(
              segments: const [
                ButtonSegment(
                  value: CustomerMessageChannel.whatsapp,
                  icon: Icon(Icons.chat_outlined),
                  label: Text('WhatsApp'),
                ),
                ButtonSegment(
                  value: CustomerMessageChannel.sms,
                  icon: Icon(Icons.sms_outlined),
                  label: Text('SMS'),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: _sending
                  ? null
                  : (values) => setState(() => _channel = values.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageController,
              minLines: 4,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _sending ? null : () => _send(api: false),
          icon: const Icon(Icons.open_in_new_outlined),
          label: const Text('Open App'),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : () => _send(api: true),
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('Send API'),
        ),
      ],
    );
  }
}
