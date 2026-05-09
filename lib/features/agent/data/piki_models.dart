import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─── Enums ───────────────────────────────────────────────────────────────────

enum PikiMode { plan, fast, sell }


enum AgentStatus { idle, thinking, working, completed }

enum PikiSender { user, agent }

enum PikiMessageType {
  text,
  thinking,
  working,
  taskComplete,
  productCard,
  error,
  aiResponse,
}

enum PikiStepStatus { pending, working, done, error }

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

  PikiStep copyWith({
    PikiStepStatus? status,
    Map<String, dynamic>? result,
  }) {
    return PikiStep(
      label: label,
      description: description,
      icon: icon,
      status: status ?? this.status,
      result: result ?? this.result,
    );
  }
}

// ─── PikiMessage ─────────────────────────────────────────────────────────────

class PikiMessage {
  final String id;
  final String content;
  final DateTime timestamp;
  final PikiSender sender;
  final PikiMessageType messageType;
  final Map<String, dynamic>? attachedData;
  final List<PikiStep>? steps;

  PikiMessage({
    String? id,
    required this.content,
    DateTime? timestamp,
    required this.sender,
    this.messageType = PikiMessageType.text,
    this.attachedData,
    this.steps,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();

  PikiMessage copyWith({
    String? content,
    PikiMessageType? messageType,
    Map<String, dynamic>? attachedData,
    List<PikiStep>? steps,
  }) {
    return PikiMessage(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp,
      sender: sender,
      messageType: messageType ?? this.messageType,
      attachedData: attachedData ?? this.attachedData,
      steps: steps ?? this.steps,
    );
  }
}
