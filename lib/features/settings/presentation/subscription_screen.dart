import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import 'subscription_plans_section.dart';

class SubscriptionScreen extends StatelessWidget {
  final bool afterSignup;
  final String? initialCountryCode;
  final String? initialProvider;
  final String? initialPlanCode;

  const SubscriptionScreen({
    super.key,
    this.afterSignup = false,
    this.initialCountryCode,
    this.initialProvider,
    this.initialPlanCode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Plans & billing',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SubscriptionPlansSection(
        fullPage: true,
        afterSignup: afterSignup,
        initialCountryCode: initialCountryCode,
        initialProvider: initialProvider,
        initialPlanCode: initialPlanCode,
        onOpenApp: () => _openApp(context),
      ),
    );
  }

  void _openApp(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AppShell(key: AppShell.shellKey)),
      (route) => false,
    );
  }
}
