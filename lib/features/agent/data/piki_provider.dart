import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/openrouter_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/utils/error_messages.dart';
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
      final isOnline = ref.watch(
        syncControllerProvider.select((state) => state.isOnline),
      );
      return PikiProactiveService.fetchInsights(allowNetwork: isOnline);
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

  Future<String> _ensureSession(String titleSeed) async {
    var sessionId = _ref.read(pikiActiveSessionIdProvider);
    if (sessionId == null) {
      final cleanTitle = titleSeed.trim().isEmpty ? 'Piki chat' : titleSeed;
      final title = cleanTitle.length > 30
          ? '${cleanTitle.substring(0, 30)}...'
          : cleanTitle;
      final session = await PikiChatRepository.createSession(title);
      sessionId = session.id;
      _ref.read(pikiActiveSessionIdProvider.notifier).state = sessionId;
      _ref.invalidate(pikiSessionsProvider);
    }

    if (_loadingFuture != null) {
      await _loadingFuture;
    }
    return sessionId;
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final sessionId = await _ensureSession(trimmed);

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

  Future<void> analyzeImage({
    required String imagePath,
    String sourceLabel = 'photo',
  }) async {
    final sessionId = await _ensureSession('Piki image scan');
    await _memoryLoadFuture;

    final label = sourceLabel.trim().isEmpty ? 'photo' : sourceLabel.trim();
    final userText =
        'Analyze this $label for a product or sale record before saving.';
    addMessage(
      PikiMessage(
        content: userText,
        sender: PikiSender.user,
        sessionId: sessionId,
      ),
    );

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final working = PikiMessage(
      content: 'Reading image with Piki AI...',
      sender: PikiSender.agent,
      sessionId: sessionId,
      messageType: PikiMessageType.working,
      steps: [
        PikiAgentService.buildStepForTool(
          PikiAgentService.toolImageOrderDraft,
        ).copyWith(status: PikiStepStatus.working),
      ],
    );
    addMessage(working);

    try {
      final result = await PikiAgentService.executeAgentTool(
        PikiAgentService.toolImageOrderDraft,
        args: {
          'image_source': imagePath,
          'note':
              'The owner wants to create a product or record a sale from this photo.',
        },
      );
      removeMessagesWhere((message) => message.id == working.id);

      final items =
          (result['items'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const <Map<String, dynamic>>[];
      final answer = items.isEmpty
          ? 'I could not read a clear product or sale line from that photo. Try a brighter, closer image with the item name and price visible.'
          : 'I read the photo and drafted ${items.length} item line${items.length == 1 ? '' : 's'}. Review them before creating a product or recording a sale.';
      final suggestions = _imageDraftSuggestions(result);

      addMessage(
        PikiMessage(
          content: answer,
          sender: PikiSender.agent,
          sessionId: sessionId,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': 'ai_response',
            'model': OpenRouterService.modelName,
            'tool_results': [result],
          },
          suggestions: suggestions.isNotEmpty ? suggestions : null,
        ),
      );
      _ref
          .read(pikiBrainProvider)
          .rememberInteraction(
            userInput: userText,
            reply: answer,
            tools: const [PikiAgentService.toolImageOrderDraft],
            results: [result],
          );
      if (items.isNotEmpty) {
        _ref.read(pikiInsightProvider.notifier).state = PikiInsightData(
          text:
              'Photo read: ${items.take(3).map((item) => item['name']).join(', ')}',
        );
      }
    } catch (error) {
      removeMessagesWhere((message) => message.id == working.id);
      addMessage(
        PikiMessage(
          content: AppErrorMessage.from(
            error,
            fallback: AppErrorMessage.pikiFailed,
          ),
          sender: PikiSender.agent,
          sessionId: sessionId,
          messageType: PikiMessageType.error,
        ),
      );
    } finally {
      statusNotifier.state = AgentStatus.idle;
    }
  }

  List<String> _imageDraftSuggestions(Map<String, dynamic> result) {
    final items =
        (result['items'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return const ['Try another clearer product photo'];
    }

    final suggestions = <String>[];
    for (final item in items.take(2)) {
      final name = (item['name'] ?? item['product_name'] ?? '')
          .toString()
          .trim();
      if (name.isEmpty) continue;
      final price = _numberFrom(item, const [
        'unit_price',
        'unitPrice',
        'price',
        'selling_price',
      ]);
      final cost = _numberFrom(item, const ['cost', 'unit_cost']);
      final stock = _numberFrom(item, const ['stock', 'initial_stock']);
      final quantity = _numberFrom(item, const ['quantity', 'qty']) ?? 1;
      final unit = (item['unit'] ?? 'pcs').toString().trim();

      final productPrompt = StringBuffer('Create product $name');
      if (price != null && price > 0) {
        productPrompt.write(' price ${price.toStringAsFixed(2)}');
      }
      if (cost != null && cost > 0) {
        productPrompt.write(' cost ${cost.toStringAsFixed(2)}');
      }
      if (stock != null && stock >= 0) {
        productPrompt.write(' stock ${stock.toStringAsFixed(2)}');
      }
      if (unit.isNotEmpty) {
        productPrompt.write(' unit $unit');
      }
      suggestions.add(productPrompt.toString());

      final salePrompt = StringBuffer('Record sale $quantity $name');
      if (price != null && price > 0) {
        salePrompt.write(' at ${price.toStringAsFixed(2)}');
      }
      salePrompt.write(' cash');
      suggestions.add(salePrompt.toString());
    }

    return suggestions.take(4).toList();
  }

  double? _numberFrom(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is num) return value.toDouble();
      if (value != null) {
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
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
    final isOnline = _ref.read(syncControllerProvider).isOnline;
    statusNotifier.state = AgentStatus.working;
    final thinking = PikiMessage(
      content: isOnline
          ? 'Checking backend signals...'
          : 'Loading saved business alerts...',
      sender: PikiSender.agent,
      messageType: PikiMessageType.working,
    );
    addMessage(thinking);

    final insights = await PikiProactiveService.fetchInsights(
      forceRefresh: isOnline,
      allowNetwork: isOnline,
    );
    _ref.invalidate(pikiProactiveInsightsProvider);
    removeMessagesWhere((message) => message.id == thinking.id);

    final summary = insights
        .take(5)
        .map((insight) => '${insight.title}: ${insight.body}')
        .join('\n');
    final content = isOnline
        ? insights.isEmpty
              ? 'No backend alerts need attention right now. Piki will keep checking from the cloud side while the backend is running.'
              : summary
        : insights.isEmpty
        ? 'You are offline and there are no saved Piki alerts on this device yet. Connect to the internet to run a fresh business check.'
        : 'You are offline. Here are the latest saved Piki alerts:\n$summary';

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
