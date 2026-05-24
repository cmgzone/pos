import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─── Enums ───────────────────────────────────────────────────────────────────

enum PikiMode { plan, fast, sell, advice }

enum AgentStatus { idle, thinking, working, completed }

enum PikiSender { user, agent }

enum PikiMessageType {
  text,
  thinking,
  working,
  taskComplete,
  productCard,
  productDraftCard,
  error,
  aiResponse,
  alert,
  chart,
}

enum PikiStepStatus { pending, working, done, error }

// ─── PikiSession ──────────────────────────────────────────────────────────────

class PikiSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  PikiSession({
    String? id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  PikiSession copyWith({String? title, DateTime? updatedAt}) {
    return PikiSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory PikiSession.fromJson(Map<String, dynamic> json) => PikiSession(
    id: json['id'] as String?,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}

// ─── PikiStep ────────────────────────────────────────────────────────────────

class PikiStep {
  final String label;
  final String description;
  final IconData icon;
  final PikiStepStatus status;
  final Map<String, dynamic>? result;

  const PikiStep({
    required this.label,
    required this.description,
    required this.icon,
    this.status = PikiStepStatus.pending,
    this.result,
  });

  PikiStep copyWith({PikiStepStatus? status, Map<String, dynamic>? result}) {
    return PikiStep(
      label: label,
      description: description,
      icon: icon,
      status: status ?? this.status,
      result: result ?? this.result,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'description': description,
    'icon': icon.codePoint,
    'status': status.name,
    'result': result,
  };

  factory PikiStep.fromJson(Map<String, dynamic> json) => PikiStep(
    label: json['label'] as String,
    description: json['description'] as String,
    icon: _decodeIcon(json['icon'] as int),
    status: PikiStepStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => PikiStepStatus.pending,
    ),
    result: json['result'] as Map<String, dynamic>?,
  );

  static IconData _decodeIcon(int codePoint) {
    // Map common Piki icons to constants to satisfy tree shaking
    if (codePoint == Icons.search_rounded.codePoint) {
      return Icons.search_rounded;
    }
    if (codePoint == Icons.bar_chart_rounded.codePoint) {
      return Icons.bar_chart_rounded;
    }
    if (codePoint == Icons.inventory_2_rounded.codePoint) {
      return Icons.inventory_2_rounded;
    }
    if (codePoint == Icons.receipt_long_rounded.codePoint) {
      return Icons.receipt_long_rounded;
    }
    if (codePoint == Icons.shopping_bag_rounded.codePoint) {
      return Icons.shopping_bag_rounded;
    }
    if (codePoint == Icons.trending_up_rounded.codePoint) {
      return Icons.trending_up_rounded;
    }
    if (codePoint == Icons.timer_rounded.codePoint) {
      return Icons.timer_rounded;
    }
    if (codePoint == Icons.event_busy_rounded.codePoint) {
      return Icons.event_busy_rounded;
    }
    if (codePoint == Icons.people_alt_rounded.codePoint) {
      return Icons.people_alt_rounded;
    }
    if (codePoint == Icons.leaderboard_rounded.codePoint) {
      return Icons.leaderboard_rounded;
    }
    if (codePoint == Icons.money_off_rounded.codePoint) {
      return Icons.money_off_rounded;
    }
    if (codePoint == Icons.local_shipping_rounded.codePoint) {
      return Icons.local_shipping_rounded;
    }
    if (codePoint == Icons.auto_awesome.codePoint) {
      return Icons.auto_awesome;
    }
    if (codePoint == Icons.note_alt_rounded.codePoint) {
      return Icons.note_alt_rounded;
    }
    if (codePoint == Icons.auto_awesome_rounded.codePoint) {
      return Icons.auto_awesome_rounded;
    }
    if (codePoint == Icons.auto_fix_high_rounded.codePoint) {
      return Icons.auto_fix_high_rounded;
    }

    // Fallback for any other icon - using a constant to avoid breaking build
    return Icons.auto_awesome_rounded;
  }
}

// ─── PikiMessage ─────────────────────────────────────────────────────────────

class PikiMessage {
  final String id;
  final String? sessionId;
  final String content;
  final DateTime timestamp;
  final PikiSender sender;
  final PikiMessageType messageType;
  final Map<String, dynamic>? attachedData;
  final List<PikiStep>? steps;
  final List<String>? suggestions;

  PikiMessage({
    String? id,
    this.sessionId,
    required this.content,
    DateTime? timestamp,
    required this.sender,
    this.messageType = PikiMessageType.text,
    this.attachedData,
    this.steps,
    this.suggestions,
  }) : id = id ?? _uuid.v4(),
       timestamp = timestamp ?? DateTime.now();

  PikiMessage copyWith({
    String? sessionId,
    String? content,
    PikiMessageType? messageType,
    Map<String, dynamic>? attachedData,
    List<PikiStep>? steps,
    List<String>? suggestions,
  }) {
    return PikiMessage(
      id: id,
      sessionId: sessionId ?? this.sessionId,
      content: content ?? this.content,
      timestamp: timestamp,
      sender: sender,
      messageType: messageType ?? this.messageType,
      attachedData: attachedData ?? this.attachedData,
      steps: steps ?? this.steps,
      suggestions: suggestions ?? this.suggestions,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'sender': sender.name,
    'messageType': messageType.name,
    'attachedData': attachedData,
    'steps': steps?.map((s) => s.toJson()).toList(),
    'suggestions': suggestions,
  };

  factory PikiMessage.fromJson(Map<String, dynamic> json) => PikiMessage(
    id: json['id'] as String?,
    sessionId: json['sessionId'] as String?,
    content: json['content'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    sender: PikiSender.values.firstWhere((e) => e.name == json['sender']),
    messageType: PikiMessageType.values.firstWhere(
      (e) => e.name == json['messageType'],
      orElse: () => PikiMessageType.text,
    ),
    attachedData: json['attachedData'] as Map<String, dynamic>?,
    steps: (json['steps'] as List?)
        ?.map((s) => PikiStep.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
    suggestions: (json['suggestions'] as List?)?.cast<String>(),
  );
}

// ─── PikiInsightData ────────────────────────────────────────────────────────

class PikiInsightData {
  final String text;
  final List<String> details;

  const PikiInsightData({required this.text, this.details = const []});
}

// ─── PikiGoal ───────────────────────────────────────────────────────────────

enum PikiGoalStatus { pending, inProgress, completed, failed }

class PikiGoal {
  final String id;
  final String description;
  final PikiGoalStatus status;
  final DateTime createdAt;
  final List<String> steps;

  PikiGoal({
    String? id,
    required this.description,
    this.status = PikiGoalStatus.pending,
    DateTime? createdAt,
    this.steps = const [],
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  PikiGoal copyWith({PikiGoalStatus? status, List<String>? steps}) {
    return PikiGoal(
      id: id,
      description: description,
      status: status ?? this.status,
      createdAt: createdAt,
      steps: steps ?? this.steps,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'steps': steps,
  };

  factory PikiGoal.fromJson(Map<String, dynamic> json) => PikiGoal(
    id: json['id'] as String?,
    description: json['description'] as String,
    status: PikiGoalStatus.values.firstWhere((e) => e.name == json['status']),
    createdAt: DateTime.parse(json['createdAt'] as String),
    steps: (json['steps'] as List?)?.cast<String>() ?? const [],
  );
}
