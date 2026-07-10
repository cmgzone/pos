import 'package:flutter/material.dart';

import 'custom_roles_section.dart';

class CustomRolesScreen extends StatelessWidget {
  const CustomRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: CustomRolesSection(),
        ),
      ),
    );
  }
}
