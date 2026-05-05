import 'package:shared_preferences/shared_preferences.dart';

class TrainingProgressSnapshot {
  final Set<String> completedModuleIds;
  final bool promptDismissed;

  const TrainingProgressSnapshot({
    required this.completedModuleIds,
    required this.promptDismissed,
  });
}

class TrainingProgressService {
  static const _completedPrefix = 'training.completed.';
  static const _promptPrefix = 'training.prompt_dismissed.';

  Future<TrainingProgressSnapshot> loadForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUserId = _normalizeUserId(userId);

    return TrainingProgressSnapshot(
      completedModuleIds: Set<String>.from(
        prefs.getStringList('$_completedPrefix$normalizedUserId') ?? const [],
      ),
      promptDismissed:
          prefs.getBool('$_promptPrefix$normalizedUserId') ?? false,
    );
  }

  Future<void> saveCompletedModules(
    String userId,
    Set<String> completedModuleIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUserId = _normalizeUserId(userId);
    final sortedIds = completedModuleIds.toList()..sort();
    await prefs.setStringList(
      '$_completedPrefix$normalizedUserId',
      sortedIds,
    );
  }

  Future<void> savePromptDismissed(String userId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUserId = _normalizeUserId(userId);
    await prefs.setBool('$_promptPrefix$normalizedUserId', value);
  }

  Future<void> reset(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUserId = _normalizeUserId(userId);
    await prefs.remove('$_completedPrefix$normalizedUserId');
    await prefs.remove('$_promptPrefix$normalizedUserId');
  }

  String _normalizeUserId(String userId) {
    final trimmed = userId.trim();
    return trimmed.isEmpty ? 'guest' : trimmed;
  }
}
