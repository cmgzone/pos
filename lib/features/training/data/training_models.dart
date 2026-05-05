import 'package:flutter/material.dart';

class TrainingRoles {
  static const admin = 'ADMIN';
  static const manager = 'MANAGER';
  static const cashier = 'CASHIER';

  static const all = {admin, manager, cashier};
  static const management = {admin, manager};
}

enum TrainingStepAction {
  none,
  openProductForm,
  openCustomerAccount,
}

class TrainingStep {
  final String id;
  final String title;
  final String description;
  final String? anchorId;
  final int? shellIndex;
  final TrainingStepAction action;
  final Set<String> allowedRoles;

  const TrainingStep({
    required this.id,
    required this.title,
    required this.description,
    this.anchorId,
    this.shellIndex,
    this.action = TrainingStepAction.none,
    this.allowedRoles = TrainingRoles.all,
  });

  bool isVisibleFor(String role) => allowedRoles.contains(role);
}

class TrainingModule {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<TrainingStep> steps;
  final Set<String> allowedRoles;

  const TrainingModule({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.steps,
    this.allowedRoles = TrainingRoles.all,
  });

  bool isVisibleFor(String role) => allowedRoles.contains(role);

  List<TrainingStep> stepsForRole(String role) => steps
      .where((step) => step.isVisibleFor(role))
      .toList(growable: false);

  int stepCountForRole(String role) => stepsForRole(role).length;
}
