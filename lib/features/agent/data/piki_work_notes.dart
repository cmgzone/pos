import 'dart:convert';

class PikiWorkNote {
  final String stage;
  final String title;
  final String detail;
  final int? loop;
  final DateTime timestamp;

  PikiWorkNote({
    required this.stage,
    required this.title,
    required this.detail,
    this.loop,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'title': title,
    'detail': detail,
    if (loop != null) 'loop': loop,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PikiWorkNote.fromJson(Map<String, dynamic> json) {
    return PikiWorkNote(
      stage: json['stage']?.toString() ?? 'planning',
      title: json['title']?.toString() ?? 'Working',
      detail: json['detail']?.toString() ?? '',
      loop: (json['loop'] as num?)?.toInt(),
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static List<PikiWorkNote> listFromJson(dynamic raw) {
    if (raw is! List) return const <PikiWorkNote>[];
    return raw
        .whereType<Map>()
        .map((item) => PikiWorkNote.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

class PikiRunState {
  final int loopCount;
  final int toolCount;
  final String stopReason;
  final bool completed;
  final bool needsUserInput;

  const PikiRunState({
    required this.loopCount,
    required this.toolCount,
    required this.stopReason,
    required this.completed,
    this.needsUserInput = false,
  });

  Map<String, dynamic> toJson() => {
    'loop_count': loopCount,
    'tool_count': toolCount,
    'stop_reason': stopReason,
    'completed': completed,
    'needs_user_input': needsUserInput,
  };

  factory PikiRunState.fromJson(Map<String, dynamic> json) {
    return PikiRunState(
      loopCount: (json['loop_count'] as num?)?.toInt() ?? 0,
      toolCount: (json['tool_count'] as num?)?.toInt() ?? 0,
      stopReason: json['stop_reason']?.toString() ?? 'unknown',
      completed: json['completed'] == true,
      needsUserInput: json['needs_user_input'] == true,
    );
  }
}

class PikiLoopDecision {
  final bool shouldStop;
  final String? reason;
  final String? detail;

  const PikiLoopDecision.continueRun()
    : shouldStop = false,
      reason = null,
      detail = null;

  const PikiLoopDecision.stop({required this.reason, required this.detail})
    : shouldStop = true;
}

class PikiAutoLoopGuard {
  static const int defaultMaxPlannerTurns = 8;
  static const int defaultMaxTotalToolCalls = 24;

  final int maxPlannerTurns;
  final int maxTotalToolCalls;
  final Set<String> _seenToolBatches = <String>{};

  PikiAutoLoopGuard({
    this.maxPlannerTurns = defaultMaxPlannerTurns,
    this.maxTotalToolCalls = defaultMaxTotalToolCalls,
  });

  bool canStartPlannerTurn(int nextLoopCount) {
    return nextLoopCount <= maxPlannerTurns;
  }

  PikiLoopDecision checkToolBatch({
    required int loopCount,
    required int totalToolCalls,
    required List<Map<String, dynamic>> toolCalls,
  }) {
    if (loopCount > maxPlannerTurns) {
      return const PikiLoopDecision.stop(
        reason: 'max_planner_turns',
        detail: 'Piki reached the planning safety limit.',
      );
    }

    if (totalToolCalls + toolCalls.length > maxTotalToolCalls) {
      return const PikiLoopDecision.stop(
        reason: 'max_total_tool_calls',
        detail: 'Piki reached the local tool safety limit.',
      );
    }

    final signature = toolBatchSignature(toolCalls);
    if (!_seenToolBatches.add(signature)) {
      return const PikiLoopDecision.stop(
        reason: 'repeated_tool_batch',
        detail: 'Piki saw the same tool request again and stopped safely.',
      );
    }

    return const PikiLoopDecision.continueRun();
  }

  static String toolBatchSignature(List<Map<String, dynamic>> toolCalls) {
    final normalized = toolCalls
        .map(
          (call) => <String, dynamic>{
            'tool': call['tool']?.toString() ?? '',
            'arguments': _normalizeJson(call['arguments']),
          },
        )
        .toList();
    return jsonEncode(normalized);
  }

  static Object? _normalizeJson(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, Object?>{
        for (final entry in entries)
          entry.key.toString(): _normalizeJson(entry.value),
      };
    }
    if (value is List) {
      return value.map(_normalizeJson).toList();
    }
    return value;
  }
}

class PikiAnswerClassifier {
  static bool needsUserInput(String answer) {
    final lower = answer.toLowerCase();
    return answer.contains('?') ||
        lower.contains('please provide') ||
        lower.contains('tell me') ||
        lower.contains('i need') ||
        lower.contains('need the') ||
        lower.contains('before i can') ||
        lower.contains('before piki can');
  }
}

class PikiLoopSummary {
  static String resultSummary(Map<String, dynamic> result) {
    return (result['summary'] ??
            result['title'] ??
            result['message'] ??
            result['tool'] ??
            result['type'] ??
            'Done')
        .toString();
  }

  static String bestEffortAnswerFromResults({
    required List<Map<String, dynamic>> results,
    required String stopReason,
  }) {
    if (results.isEmpty) {
      return 'I paused before running more work because $stopReason. Please try again with one specific request.';
    }
    final resultLines = results
        .take(5)
        .map((result) => '- ${resultSummary(result)}')
        .join('\n');
    return 'I completed the local checks I could finish, then paused because $stopReason. Key results:\n$resultLines';
  }
}
