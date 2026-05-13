import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigator.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../app/app_shell.dart';
import '../../customers/presentation/customer_account_screen.dart';
import '../../products/presentation/product_form_screen.dart';
import '../data/training_models.dart';
import '../data/training_modules.dart';
import '../data/training_progress_service.dart';

final trainingControllerProvider = ChangeNotifierProvider<TrainingController>(
  (ref) => TrainingController(progressService: TrainingProgressService()),
);

class TrainingController extends ChangeNotifier {
  TrainingController({required TrainingProgressService progressService})
    : _progressService = progressService {
    ensureLoadedForCurrentUser();
  }

  final TrainingProgressService _progressService;

  String _loadedUserId = '';
  bool _isLoaded = false;
  bool _promptDismissed = false;
  Set<String> _completedModuleIds = <String>{};
  String? _activeModuleId;
  int _stepIndex = 0;
  List<String> _queuedModuleIds = <String>[];
  String? _lastActionExecutionKey;

  String get _currentRole =>
      RolePermissions.normalizeRole(SessionService.currentUserRole);

  bool get isLoaded => _isLoaded;
  bool get isActive => _activeModuleId != null;
  bool get canGoBack => _stepIndex > 0;

  List<TrainingModule> get availableModules {
    final modules = <TrainingModule>[];
    for (final module in availableTrainingModules(_currentRole)) {
      if (!_canAccessTrainingModule(module)) {
        continue;
      }
      final steps = module.steps
          .where(
            (step) =>
                step.isVisibleFor(_currentRole) && _canAccessTrainingStep(step),
          )
          .toList(growable: false);
      if (steps.isEmpty) {
        continue;
      }
      modules.add(
        TrainingModule(
          id: module.id,
          title: module.title,
          description: module.description,
          icon: module.icon,
          steps: steps,
          allowedRoles: module.allowedRoles,
        ),
      );
    }
    return modules;
  }

  int get completedModuleCount => availableModules
      .where((module) => _completedModuleIds.contains(module.id))
      .length;

  int get availableModuleCount => availableModules.length;

  double get completionRatio {
    if (availableModuleCount == 0) {
      return 0;
    }
    return completedModuleCount / availableModuleCount;
  }

  bool get shouldShowPrompt =>
      _isLoaded &&
      !isActive &&
      !_promptDismissed &&
      completedModuleCount == 0 &&
      availableModuleCount > 0;

  TrainingModule? get activeModule {
    final moduleId = _activeModuleId;
    if (moduleId == null) {
      return null;
    }
    for (final module in availableModules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }

  List<TrainingStep> get activeSteps =>
      activeModule?.stepsForRole(_currentRole) ?? const <TrainingStep>[];

  TrainingStep? get currentStep {
    if (!isActive || activeSteps.isEmpty) {
      return null;
    }
    if (_stepIndex < 0 || _stepIndex >= activeSteps.length) {
      return null;
    }
    return activeSteps[_stepIndex];
  }

  int get currentStepNumber => currentStep == null ? 0 : _stepIndex + 1;
  int get totalStepCount => activeSteps.length;

  String get nextButtonLabel {
    if (currentStep == null) {
      return 'Next';
    }
    if (_stepIndex < activeSteps.length - 1) {
      return 'Next';
    }
    return _queuedModuleIds.isEmpty ? 'Finish' : 'Next Module';
  }

  bool isModuleCompleted(String moduleId) =>
      _completedModuleIds.contains(moduleId);

  Future<void> ensureLoadedForCurrentUser() async {
    final userId = _normalizeUserId(SessionService.currentUserId);
    if (_isLoaded && userId == _loadedUserId) {
      return;
    }

    final snapshot = await _progressService.loadForUser(userId);
    _loadedUserId = userId;
    _completedModuleIds = snapshot.completedModuleIds;
    _promptDismissed = snapshot.promptDismissed;
    _activeModuleId = null;
    _stepIndex = 0;
    _queuedModuleIds = <String>[];
    _lastActionExecutionKey = null;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> dismissPrompt() async {
    await ensureLoadedForCurrentUser();
    if (_promptDismissed) {
      return;
    }
    _promptDismissed = true;
    await _progressService.savePromptDismissed(_loadedUserId, true);
    notifyListeners();
  }

  Future<void> startFullTour() async {
    await ensureLoadedForCurrentUser();
    final availableIds = fullTrainingOrder
        .where(
          (moduleId) => availableModules.any((module) => module.id == moduleId),
        )
        .toList(growable: false);
    if (availableIds.isEmpty) {
      return;
    }

    await startModule(
      availableIds.first,
      queuedModuleIds: availableIds.skip(1).toList(growable: false),
    );
  }

  Future<void> startModule(
    String moduleId, {
    List<String> queuedModuleIds = const <String>[],
  }) async {
    await ensureLoadedForCurrentUser();
    if (!availableModules.any((module) => module.id == moduleId)) {
      return;
    }

    await _returnToShellSurface();
    _activeModuleId = moduleId;
    _stepIndex = 0;
    _queuedModuleIds = List<String>.from(queuedModuleIds);
    _lastActionExecutionKey = null;
    _promptDismissed = true;
    await _progressService.savePromptDismissed(_loadedUserId, true);
    notifyListeners();
    await _syncCurrentStepContext();
  }

  Future<void> nextStep() async {
    final step = currentStep;
    if (step == null) {
      return;
    }

    if (_stepIndex < activeSteps.length - 1) {
      _stepIndex += 1;
      _lastActionExecutionKey = null;
      notifyListeners();
      await _syncCurrentStepContext();
      return;
    }

    await _completeActiveModule();
  }

  Future<void> previousStep() async {
    if (!canGoBack) {
      return;
    }
    _stepIndex -= 1;
    _lastActionExecutionKey = null;
    notifyListeners();
    await _syncCurrentStepContext();
  }

  Future<void> replayCurrentStepAction() async {
    final step = currentStep;
    if (step == null || step.action == TrainingStepAction.none) {
      return;
    }
    await _performStepAction(step, force: true);
    notifyListeners();
  }

  Future<void> cancelTraining() async {
    if (!isActive) {
      return;
    }
    _activeModuleId = null;
    _stepIndex = 0;
    _queuedModuleIds = <String>[];
    _lastActionExecutionKey = null;
    notifyListeners();
    await _returnToShellSurface();
  }

  Future<void> resetProgress() async {
    await ensureLoadedForCurrentUser();
    _completedModuleIds.clear();
    _promptDismissed = false;
    _activeModuleId = null;
    _stepIndex = 0;
    _queuedModuleIds = <String>[];
    _lastActionExecutionKey = null;
    await _progressService.reset(_loadedUserId);
    notifyListeners();
  }

  String actionLabelFor(TrainingStep step) {
    switch (step.action) {
      case TrainingStepAction.openProductForm:
        return 'Open Product Form';
      case TrainingStepAction.openCustomerAccount:
        return 'Open Customer Form';
      case TrainingStepAction.none:
        return 'Open';
    }
  }

  Future<void> _completeActiveModule() async {
    final moduleId = _activeModuleId;
    if (moduleId == null) {
      return;
    }

    _completedModuleIds = <String>{..._completedModuleIds, moduleId};
    await _progressService.saveCompletedModules(
      _loadedUserId,
      _completedModuleIds,
    );

    if (_queuedModuleIds.isNotEmpty) {
      final nextModuleId = _queuedModuleIds.removeAt(0);
      _activeModuleId = nextModuleId;
      _stepIndex = 0;
      _lastActionExecutionKey = null;
      notifyListeners();
      await _syncCurrentStepContext();
      return;
    }

    _activeModuleId = null;
    _stepIndex = 0;
    _queuedModuleIds = <String>[];
    _lastActionExecutionKey = null;
    notifyListeners();
    await _returnToShellSurface();
  }

  Future<void> _syncCurrentStepContext() async {
    final step = currentStep;
    if (step == null) {
      return;
    }

    if (step.shellIndex != null) {
      await _showShellScreen(step.shellIndex!);
    }

    await _performStepAction(step);
    notifyListeners();
  }

  Future<void> _showShellScreen(int index) async {
    await _returnToShellSurface();
    AppShell.selectIndex(index);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _performStepAction(
    TrainingStep step, {
    bool force = false,
  }) async {
    if (step.action == TrainingStepAction.none) {
      return;
    }

    final actionKey =
        '${_activeModuleId ?? ''}:$_stepIndex:${step.action.name}';
    if (!force && _lastActionExecutionKey == actionKey) {
      return;
    }
    _lastActionExecutionKey = actionKey;

    final navigator = AppNavigator.state;
    if (navigator == null) {
      return;
    }

    switch (step.action) {
      case TrainingStepAction.none:
        break;
      case TrainingStepAction.openProductForm:
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const ProductFormScreen()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        break;
      case TrainingStepAction.openCustomerAccount:
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const CustomerAccountScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        break;
    }
  }

  Future<void> _returnToShellSurface() async {
    final navigator = AppNavigator.state;
    if (navigator == null) {
      return;
    }
    navigator.popUntil((route) => route.isFirst);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  bool _canAccessTrainingModule(TrainingModule module) {
    final feature = _featureForModule(module.id);
    return feature == null || _canUseFeature(feature);
  }

  bool _canAccessTrainingStep(TrainingStep step) {
    final shellIndex = step.shellIndex;
    if (shellIndex != null) {
      if (!SessionService.canAccessNavigationIndex(shellIndex)) {
        return false;
      }
      final feature = UserAccessProfile.featureForNavigationIndex(shellIndex);
      if (feature != null && !_canUseFeature(feature)) {
        return false;
      }
    }

    switch (step.action) {
      case TrainingStepAction.openProductForm:
        return _canUseFeature(UserAccessProfile.featureProducts);
      case TrainingStepAction.openCustomerAccount:
        return _canUseFeature(UserAccessProfile.featureKopesha);
      case TrainingStepAction.none:
        return true;
    }
  }

  bool _canUseFeature(String feature) {
    return SessionService.canAccessFeature(feature) &&
        LicenseService.currentSnapshot.allowsFeature(feature);
  }

  String? _featureForModule(String moduleId) {
    switch (moduleId) {
      case 'pos':
        return UserAccessProfile.featurePos;
      case 'dashboard':
        return UserAccessProfile.featureDashboard;
      case 'products':
        return UserAccessProfile.featureProducts;
      case 'categories':
        return UserAccessProfile.featureCategories;
      case 'purchases':
        return UserAccessProfile.featurePurchases;
      case 'sales':
        return UserAccessProfile.featureSales;
      case 'kopesha':
        return UserAccessProfile.featureKopesha;
      case 'profit-loss':
        return UserAccessProfile.featureProfitLoss;
      case 'reports':
        return UserAccessProfile.featureReports;
      case 'settings':
        return UserAccessProfile.featureSettings;
      case 'services':
        return UserAccessProfile.featureServices;
      default:
        return null;
    }
  }

  String _normalizeUserId(String userId) {
    final trimmed = userId.trim();
    return trimmed.isEmpty ? 'guest' : trimmed;
  }
}
