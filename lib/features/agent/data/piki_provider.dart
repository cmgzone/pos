import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/openrouter_service.dart';
import 'piki_agent_service.dart';
import 'piki_brain_service.dart';
import 'piki_chat_repository.dart';
import 'piki_memory_service.dart';
import 'piki_models.dart';
import 'piki_proactive_service.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final pikiModeProvider = StateProvider<PikiMode>((ref) => PikiMode.plan);

final pikiStatusProvider = StateProvider<AgentStatus>(
  (ref) => AgentStatus.idle,
);

final pikiInsightProvider = StateProvider<PikiInsightData?>((ref) => null);

/// Navigation signal — avoids circular import with app_shell.dart.
enum PikiNavTarget { none, pos }

final pikiNavigateProvider = StateProvider<PikiNavTarget>(
  (ref) => PikiNavTarget.none,
);

final pikiActiveSessionIdProvider = StateProvider<String?>((ref) => null);

final pikiSessionsProvider = FutureProvider<List<PikiSession>>((ref) {
  return PikiChatRepository.getAllSessions();
});

final pikiProactiveInsightsProvider =
    FutureProvider<List<PikiProactiveInsight>>((ref) {
      return PikiProactiveService.fetchInsights();
    });

final pikiMessagesProvider =
    StateNotifierProvider<PikiMessagesNotifier, List<PikiMessage>>(
      (ref) => PikiMessagesNotifier(ref),
    );

// ─── Notifier ────────────────────────────────────────────────────────────────

class PikiMessagesNotifier extends StateNotifier<List<PikiMessage>> {
  final Ref _ref;
  late final Future<void> _memoryLoadFuture;
  Future<void>? _loadingFuture;

  PikiMessagesNotifier(this._ref) : super([]) {
    _memoryLoadFuture = _restoreMemory();
    _loadingFuture = _loadSessionMessages(
      _ref.read(pikiActiveSessionIdProvider),
    );
    _ref.listen(pikiActiveSessionIdProvider, (previous, next) {
      if (previous != next) {
        _loadingFuture = _loadSessionMessages(next);
      }
    });
  }

  Future<void> _loadSessionMessages(String? sessionId) async {
    if (sessionId == null) {
      state = [];
      return;
    }
    final messages = await PikiChatRepository.getMessages(sessionId);
    if (_ref.read(pikiActiveSessionIdProvider) == sessionId) {
      state = messages;
    }
  }

  void addMessage(PikiMessage msg) {
    final sessionId = _ref.read(pikiActiveSessionIdProvider);
    final toSave = msg.sessionId == null
        ? msg.copyWith(sessionId: sessionId)
        : msg;
    state = [...state, toSave];
    if (toSave.sessionId != null &&
        toSave.messageType != PikiMessageType.thinking &&
        toSave.messageType != PikiMessageType.working) {
      unawaited(PikiChatRepository.saveMessage(toSave));
    }
  }

  void replaceMessage(String id, PikiMessage updated) {
    state = state.map((m) => m.id == id ? updated : m).toList();
    if (updated.sessionId != null &&
        updated.messageType != PikiMessageType.thinking &&
        updated.messageType != PikiMessageType.working) {
      unawaited(PikiChatRepository.saveMessage(updated));
    }
  }

  void removeMessagesWhere(bool Function(PikiMessage) test) {
    state = state.where((m) => !test(m)).toList();
  }

  void persistMemory({
    required List<Map<String, dynamic>> memoryTurns,
    required Map<String, Map<String, dynamic>> lastToolResults,
    required Map<String, dynamic>? pendingPurchaseDraft,
  }) {
    unawaited(PikiMemoryService.saveMemory('memoryTurns', memoryTurns));
    unawaited(PikiMemoryService.saveMemory('lastToolResults', lastToolResults));
    unawaited(
      PikiMemoryService.saveMemory(
        'pendingPurchaseDraft',
        pendingPurchaseDraft,
      ),
    );
  }

  Future<void> _restoreMemory() async {
    final turns = await PikiMemoryService.getMemory('memoryTurns');
    final results = await PikiMemoryService.getMemory('lastToolResults');
    final draft = await PikiMemoryService.getMemory('pendingPurchaseDraft');
    final aliases = await PikiMemoryService.getMemory('posAliases');
    final lastCart = await PikiMemoryService.getMemory('posLastCart');

    _ref
        .read(pikiBrainProvider)
        .loadMemory(
          memoryTurns:
              (turns as List?)
                  ?.whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList() ??
              [],
          lastToolResults:
              (results as Map?)?.map(
                (k, v) =>
                    MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
              ) ??
              {},
          pendingPurchaseDraft: draft != null
              ? Map<String, dynamic>.from(draft as Map)
              : null,
        );
    _ref
        .read(pikiBrainProvider)
        .loadPosMemory(
          aliases:
              (aliases as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ) ??
              const <String, String>{},
          lastCart: lastCart != null
              ? Map<String, dynamic>.from(lastCart as Map)
              : null,
        );
  }

  // ── Public API ─────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    var sessionId = _ref.read(pikiActiveSessionIdProvider);
    if (sessionId == null) {
      final title = trimmed.length > 30
          ? '${trimmed.substring(0, 30)}...'
          : trimmed;
      final session = await PikiChatRepository.createSession(title);
      sessionId = session.id;
      _ref.read(pikiActiveSessionIdProvider.notifier).state = sessionId;
      _ref.invalidate(pikiSessionsProvider);
    }

    if (_loadingFuture != null) {
      await _loadingFuture;
    }

    // User bubble
    addMessage(
      PikiMessage(
        content: trimmed,
        sender: PikiSender.user,
        sessionId: sessionId,
      ),
    );
    await _memoryLoadFuture;

    if (_isProactivePrompt(trimmed)) {
      await _sendProactiveBrief(trimmed);
      return;
    }

    final mode = _ref.read(pikiModeProvider);
    final brain = _ref.read(pikiBrainProvider);

    if (brain.isPurchaseDraftCancel(trimmed)) {
      brain.discardPendingPurchaseDraft(trimmed);
      return;
    }
    if (brain.isPurchaseDraftConfirm(trimmed)) {
      await brain.confirmPendingPurchaseDraft(trimmed);
      return;
    }

    var aiEnabled = OpenRouterService.isEnabled;
    brain.resetError();
    if (!aiEnabled) {
      aiEnabled = await OpenRouterService.refreshConfig();
    }
    if (aiEnabled) {
      final handled = await brain.executeModelDrivenAgent(trimmed, mode);
      if (handled) return;
    }

    final skills = PikiAgentService.matchSkills(trimmed);

    if (skills.isEmpty) {
      if (aiEnabled) {
        if (brain.lastError != null) {
          addMessage(
            PikiMessage(
              content: 'I could not complete that request. ${brain.lastError}',
              sender: PikiSender.agent,
              messageType: PikiMessageType.error,
            ),
          );
          return;
        }
        await brain.executeAiChat(trimmed, mode);
        return;
      }
      addMessage(
        PikiMessage(
          content:
              'I could not understand that request. ${brain.lastError ?? ""}',
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      );
      return;
    }

    if (mode == PikiMode.plan ||
        mode == PikiMode.advice ||
        mode == PikiMode.sell) {
      await brain.executePlanMode(skills);
    } else {
      await brain.executeFastMode(skills);
    }
  }

  void executeQuickAction(String action) => sendMessage(action);

  bool _isProactivePrompt(String text) {
    final lower = text.toLowerCase();
    return lower.contains('proactive') ||
        lower.contains('business alerts') ||
        lower.contains('what should i watch') ||
        lower.contains('what needs attention') ||
        lower.contains('keep an eye');
  }

  Future<void> _sendProactiveBrief(String userInput) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final thinking = PikiMessage(
      content: 'Checking backend signals...',
      sender: PikiSender.agent,
      messageType: PikiMessageType.working,
    );
    addMessage(thinking);

    final insights = await PikiProactiveService.fetchInsights(
      forceRefresh: true,
    );
    removeMessagesWhere((message) => message.id == thinking.id);

    final content = insights.isEmpty
        ? 'No backend alerts need attention right now. Piki will keep checking from the cloud side while the backend is running.'
        : insights
              .take(5)
              .map((insight) => '${insight.title}: ${insight.body}')
              .join('\n');

    addMessage(
      PikiMessage(
        content: content,
        sender: PikiSender.agent,
        messageType: PikiMessageType.aiResponse,
        attachedData: {
          'type': 'proactive_insights',
          'insights': insights
              .map(
                (insight) => {
                  'id': insight.id,
                  'severity': insight.severity,
                  'kind': insight.kind,
                  'title': insight.title,
                  'body': insight.body,
                  'action': insight.action,
                },
              )
              .toList(),
        },
      ),
    );
    _ref
        .read(pikiBrainProvider)
        .rememberInteraction(
          userInput: userInput,
          reply: content,
          tools: const ['proactive_insights'],
        );
    statusNotifier.state = AgentStatus.idle;
  }
}
