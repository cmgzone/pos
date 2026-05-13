import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/openrouter_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../sales/data/held_sale_provider.dart';
import '../../sales/data/held_sale_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../sales/data/cart_provider.dart';
import '../../services/data/service_repository.dart';
import 'piki_agent_service.dart';
import 'piki_memory_service.dart';
import 'piki_models.dart';
import 'piki_pos_command_engine.dart';
import 'piki_proactive_service.dart';
import 'piki_provider.dart';
import 'piki_work_notes.dart';

final pikiBrainProvider = Provider<PikiBrainService>((ref) {
  return PikiBrainService(ref);
});

class PikiBrainService {
  final Ref _ref;
  final List<Map<String, dynamic>> _memoryTurns = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _lastToolResults =
      <String, Map<String, dynamic>>{};
  Map<String, dynamic>? _pendingPurchaseDraft;
  final Map<String, String> _posAliases = <String, String>{};
  String? _lastSellQuery;
  String? _lastCartKey;
  String? _lastCartLabel;
  String? _lastPlannerError;

  PikiBrainService(this._ref);

  PikiMessagesNotifier get _messagesNotifier =>
      _ref.read(pikiMessagesProvider.notifier);

  List<PikiMessage> get _messages => _ref.read(pikiMessagesProvider);

  void resetError() => _lastPlannerError = null;
  String? get lastError => _lastPlannerError;

  List<PikiStep> _cloneSteps(List<PikiStep> source) => source
      .map(
        (s) => PikiStep(
          label: s.label,
          description: s.description,
          icon: s.icon,
          status: s.status,
          result: s.result,
        ),
      )
      .toList();

  void _publishInsightFromResults(Map<String, dynamic> allResults) {
    if (allResults.isEmpty) return;
    final first = allResults.values.first;
    if (first is Map<String, dynamic>) {
      _ref.read(pikiInsightProvider.notifier).state = const PikiInsightData(
        text: 'Analyzing...',
      );
      PikiAgentService.generateInsight(first).then((insight) {
        _ref.read(pikiInsightProvider.notifier).state = insight;
      });
    }
  }

  List<Map<String, String>> _conversationForPlanner() {
    final messages = _messages
        .where(
          (message) =>
              message.messageType != PikiMessageType.thinking &&
              message.messageType != PikiMessageType.working,
        )
        .toList();
    final slice = messages.length > 8
        ? messages.sublist(messages.length - 8)
        : messages;
    return slice
        .map(
          (message) => {
            'role': message.sender == PikiSender.user ? 'user' : 'assistant',
            'content': message.content,
          },
        )
        .toList();
  }

  String _memorySummary() {
    if (_memoryTurns.isEmpty &&
        _lastToolResults.isEmpty &&
        _posAliases.isEmpty &&
        _lastCartLabel == null) {
      return 'No follow-up memory yet.';
    }
    final lines = <String>[];
    if (_posAliases.isNotEmpty) {
      lines.add(
        'Cashier aliases: ${_posAliases.entries.map((entry) => '${entry.key} means ${entry.value}').take(8).join('; ')}.',
      );
    }
    if (_lastCartLabel != null) {
      lines.add('Last cart item: $_lastCartLabel.');
    }
    if (_pendingPurchaseDraft != null) {
      final count = (_pendingPurchaseDraft?['count'] as num? ?? 0).toInt();
      final supplier = _pendingPurchaseDraft?['preferred_supplier'] as String?;
      lines.add(
        'Pending purchase draft: $count item(s)'
        '${supplier == null || supplier.isEmpty ? '' : ' with preferred supplier $supplier'}.',
      );
    }
    if (_memoryTurns.isNotEmpty) {
      lines.add('Recent turns:');
      for (final turn in _memoryTurns.take(4)) {
        final tools =
            (turn['tools'] as List?)?.whereType<String>().join(', ') ?? '';
        lines.add(
          '- User: ${turn['user']} | Reply: ${turn['reply']}'
          '${tools.isEmpty ? '' : ' | Tools: $tools'}',
        );
      }
    }
    if (_lastToolResults.isNotEmpty) {
      lines.add('Latest tool results:');
      for (final entry in _lastToolResults.entries.take(6)) {
        final r = entry.value;
        final summary = r['summary'] ?? r['title'] ?? 'available';
        final extra = <String>[];
        if (r['total_revenue'] != null) extra.add('Rev: ${r['total_revenue']}');
        if (r['total_profit'] != null) {
          extra.add('Profit: ${r['total_profit']}');
        }
        if (r['total_sales'] != null) extra.add('Sales: ${r['total_sales']}');
        if (r['total_amount'] != null) {
          extra.add('Amount: ${r['total_amount']}');
        }
        if (r['count'] != null) extra.add('Count: ${r['count']}');

        lines.add(
          '- ${entry.key}: $summary${extra.isEmpty ? '' : ' (${extra.join(', ')})'}',
        );
      }
    }
    return lines.join('\n');
  }

  void rememberInteraction({
    required String userInput,
    required String reply,
    List<String> tools = const <String>[],
    List<Map<String, dynamic>> results = const <Map<String, dynamic>>[],
  }) {
    _memoryTurns.insert(0, {
      'user': userInput,
      'reply': reply,
      'tools': tools,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_memoryTurns.length > 6) {
      _memoryTurns.removeRange(6, _memoryTurns.length);
    }

    for (final result in results) {
      final tool = result['tool'] as String?;
      final type = result['type'] as String?;
      if (tool != null && tool.isNotEmpty) {
        _lastToolResults[tool] = result;
      }
      if (type != null && type.isNotEmpty) {
        _lastToolResults[type] = result;
      }
      if (tool == PikiAgentService.toolPurchaseDraft &&
          (result['count'] as num? ?? 0) > 0) {
        _pendingPurchaseDraft = result;
      }
    }
    _messagesNotifier.persistMemory(
      memoryTurns: _memoryTurns,
      lastToolResults: _lastToolResults,
      pendingPurchaseDraft: _pendingPurchaseDraft,
    );
  }

  void loadMemory({
    required List<Map<String, dynamic>> memoryTurns,
    required Map<String, Map<String, dynamic>> lastToolResults,
    required Map<String, dynamic>? pendingPurchaseDraft,
  }) {
    _memoryTurns.clear();
    _memoryTurns.addAll(memoryTurns);
    _lastToolResults.clear();
    _lastToolResults.addAll(lastToolResults);
    _pendingPurchaseDraft = pendingPurchaseDraft;
  }

  void loadPosMemory({
    required Map<String, String> aliases,
    required Map<String, dynamic>? lastCart,
  }) {
    _posAliases
      ..clear()
      ..addAll(aliases);
    _lastSellQuery = lastCart?['query'] as String?;
    _lastCartKey = lastCart?['cartKey'] as String?;
    _lastCartLabel = lastCart?['label'] as String?;
  }

  Future<void> _persistPosMemory() async {
    await PikiMemoryService.saveMemory('posAliases', _posAliases);
    await PikiMemoryService.saveMemory('posLastCart', {
      'query': _lastSellQuery,
      'cartKey': _lastCartKey,
      'label': _lastCartLabel,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  ({List<Map<String, dynamic>> calls, List<String> skipped})
  _normalizeToolCalls(dynamic rawToolCalls) {
    if (rawToolCalls is! List) {
      return (calls: const <Map<String, dynamic>>[], skipped: const <String>[]);
    }
    final normalized = <Map<String, dynamic>>[];
    final skipped = <String>[];
    for (final call in rawToolCalls) {
      if (call is Map) {
        final toolName = call['tool']?.toString().trim();
        if (toolName != null && toolName.isNotEmpty) {
          if (!PikiAgentService.isKnownTool(toolName)) {
            skipped.add(toolName);
            continue; // Skip hallucinated tools
          }
          final Map<String, dynamic> args = {};
          if (call['arguments'] is Map) {
            for (final entry in (call['arguments'] as Map).entries) {
              args[entry.key.toString()] = entry.value;
            }
          }
          normalized.add({
            'tool': toolName,
            'reason': call['reason']?.toString() ?? '',
            'arguments': args,
          });
        }
      }
    }
    return (calls: normalized, skipped: skipped);
  }

  List<Map<String, dynamic>> _collectCitations(
    List<Map<String, dynamic>> allResults,
  ) {
    final citations = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addCitation(String label, String detail) {
      final cleanLabel = label.trim();
      final cleanDetail = detail.trim();
      if (cleanLabel.isEmpty) return;
      final key = '$cleanLabel|$cleanDetail';
      if (!seen.add(key)) return;
      citations.add({
        'index': citations.length + 1,
        'label': cleanLabel,
        'detail': cleanDetail,
      });
    }

    for (final r in allResults) {
      final toolCitations = r['citations'];
      if (toolCitations is List) {
        for (final citation in toolCitations) {
          if (citation is Map) {
            addCitation(
              citation['label']?.toString() ?? 'Source',
              citation['detail']?.toString() ?? '',
            );
          }
        }
      }

      final items = r['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            final name =
                item['name'] as String? ?? item['product_name'] as String?;
            final link = item['link'] as String?;
            if (name != null) {
              addCitation(name, link ?? 'Source row from tool result.');
            } else if ((item['title'] as String?)?.isNotEmpty == true) {
              addCitation(
                item['title'] as String,
                link ?? item['snippet']?.toString() ?? '',
              );
            }
          }
        }
      }
      if (r['type'] == 'sales_report') {
        addCitation('Sales Data', 'Recorded sales in the local POS database.');
      }
      if (r['type'] == 'today_summary') {
        addCitation("Today's Summary", 'Local POS summary data.');
      }
    }
    return citations;
  }

  Map<String, dynamic> _workNotesAttachedData(
    List<PikiWorkNote> notes, {
    PikiRunState? runState,
    String? type,
  }) {
    final data = <String, dynamic>{
      'work_notes': notes.map((note) => note.toJson()).toList(),
    };
    if (type != null) {
      data['type'] = type;
    }
    if (runState != null) {
      data['run_state'] = runState.toJson();
    }
    return data;
  }

  void _addWorkNote(
    List<PikiWorkNote> notes, {
    required String stage,
    required String title,
    required String detail,
    int? loop,
  }) {
    final cleanDetail = detail.trim();
    notes.add(
      PikiWorkNote(
        stage: stage,
        title: title,
        detail: cleanDetail.length > 220
            ? '${cleanDetail.substring(0, 217)}...'
            : cleanDetail,
        loop: loop,
      ),
    );
  }

  String _describeToolCalls(List<Map<String, dynamic>> toolCalls) {
    return toolCalls
        .map((call) {
          final tool = call['tool']?.toString() ?? 'tool';
          final reason = call['reason']?.toString().trim() ?? '';
          return reason.isEmpty ? tool : '$tool: $reason';
        })
        .join('; ');
  }

  String _resultSummary(Map<String, dynamic> result) {
    return PikiLoopSummary.resultSummary(result);
  }

  String _bestEffortAnswerFromResults({
    required List<Map<String, dynamic>> results,
    required String stopReason,
  }) {
    return PikiLoopSummary.bestEffortAnswerFromResults(
      results: results,
      stopReason: stopReason,
    );
  }

  bool _looksLikeUserInputRequest(String answer) {
    return PikiAnswerClassifier.needsUserInput(answer);
  }

  void _resetStatusAfterDelay(StateController<AgentStatus> statusNotifier) {
    Future.delayed(const Duration(milliseconds: 300), () {
      statusNotifier.state = AgentStatus.idle;
    });
  }

  // ── AI Chat (OpenRouter) ──────────────────────────────────────────────

  Future<void> executeAiChat(String text, PikiMode mode) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.thinking;

    _messagesNotifier.addMessage(
      PikiMessage(
        content: 'Thinking...',
        sender: PikiSender.agent,
        messageType: PikiMessageType.thinking,
      ),
    );

    try {
      final recentMessages = _messages
          .where(
            (m) =>
                m.messageType != PikiMessageType.thinking &&
                m.messageType != PikiMessageType.working,
          )
          .toList();
      final historySlice = recentMessages.length > 10
          ? recentMessages.sublist(recentMessages.length - 10)
          : recentMessages;

      final messages = historySlice.map((m) {
        return {
          'role': m.sender == PikiSender.user ? 'user' : 'assistant',
          'content': m.content,
        };
      }).toList();

      final response = await OpenRouterService.chat(
        messages: messages,
        includeBusinessContext:
            mode == PikiMode.plan ||
            mode == PikiMode.advice ||
            mode == PikiMode.sell,
      );

      _messagesNotifier.removeMessagesWhere(
        (m) => m.messageType == PikiMessageType.thinking,
      );

      _messagesNotifier.addMessage(
        PikiMessage(
          content: response,
          sender: PikiSender.agent,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': 'ai_response',
            'model': OpenRouterService.modelName,
          },
        ),
      );
      rememberInteraction(userInput: text, reply: response);
    } catch (e) {
      _messagesNotifier.removeMessagesWhere(
        (m) => m.messageType == PikiMessageType.thinking,
      );

      _messagesNotifier.addMessage(
        PikiMessage(
          content: '$e',
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      );
    }

    _resetStatusAfterDelay(statusNotifier);
  }

  // ── Plan mode ──────────────────────────────────────────────────────────

  Future<void> executePlanMode(List<PikiSkill> skills) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.thinking;

    final steps = PikiAgentService.buildSteps(skills);

    final thinkingMsg = PikiMessage(
      content: 'Thinking...',
      sender: PikiSender.agent,
      messageType: PikiMessageType.thinking,
      steps: steps,
    );
    _messagesNotifier.addMessage(thinkingMsg);
    await Future<void>.delayed(const Duration(milliseconds: 900));

    statusNotifier.state = AgentStatus.working;
    final workingMsg = PikiMessage(
      content: 'Completing tasks... 0 of ${skills.length}',
      sender: PikiSender.agent,
      messageType: PikiMessageType.working,
      steps: List<PikiStep>.from(steps),
    );
    _messagesNotifier.addMessage(workingMsg);

    final allResults = <String, dynamic>{};
    final completedDetails = <String>[];

    for (int i = 0; i < skills.length; i++) {
      final updatedSteps = _cloneSteps(workingMsg.steps!);
      for (int j = 0; j < i; j++) {
        updatedSteps[j] = updatedSteps[j].copyWith(status: PikiStepStatus.done);
      }
      updatedSteps[i] = updatedSteps[i].copyWith(
        status: PikiStepStatus.working,
      );

      _messagesNotifier.replaceMessage(
        workingMsg.id,
        workingMsg.copyWith(
          steps: updatedSteps,
          content: 'Completing tasks... ${i + 1} of ${skills.length}',
        ),
      );

      try {
        final result = await PikiAgentService.executeSkill(skills[i]);
        allResults[skills[i].name] = result;
        completedDetails.add(result['summary'] as String? ?? 'Done');
        updatedSteps[i] = updatedSteps[i].copyWith(
          status: PikiStepStatus.done,
          result: result,
        );
        _messagesNotifier.replaceMessage(
          workingMsg.id,
          workingMsg.copyWith(steps: updatedSteps),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } catch (e) {
        updatedSteps[i] = updatedSteps[i].copyWith(
          status: PikiStepStatus.error,
        );
        completedDetails.add('Error: $e');
      }
    }

    _messagesNotifier.replaceMessage(
      thinkingMsg.id,
      thinkingMsg.copyWith(
        steps: steps
            .map((s) => s.copyWith(status: PikiStepStatus.done))
            .toList(),
      ),
    );

    _messagesNotifier.addMessage(
      PikiMessage(
        content: 'Tasks completed',
        sender: PikiSender.agent,
        messageType: PikiMessageType.taskComplete,
        attachedData: {
          'results': allResults,
          'details': completedDetails,
          'skill_count': skills.length,
        },
      ),
    );

    _publishInsightFromResults(allResults);
    _resetStatusAfterDelay(statusNotifier);
  }

  // ── Fast mode ──────────────────────────────────────────────────────────

  Future<void> executeFastMode(List<PikiSkill> skills) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;

    for (final skill in skills) {
      try {
        final result = await PikiAgentService.executeSkill(skill);
        final hasItems = ((result['items'] as List?)?.isNotEmpty ?? false);

        _messagesNotifier.addMessage(
          PikiMessage(
            content: result['summary'] as String? ?? 'Done',
            sender: PikiSender.agent,
            messageType: hasItems
                ? PikiMessageType.productCard
                : PikiMessageType.taskComplete,
            attachedData: result,
          ),
        );

        _ref.read(pikiInsightProvider.notifier).state = const PikiInsightData(
          text: 'Analyzing...',
        );
        PikiAgentService.generateInsight(result).then((insight) {
          _ref.read(pikiInsightProvider.notifier).state = insight;
        });
      } catch (e) {
        _messagesNotifier.addMessage(
          PikiMessage(
            content: 'Error: $e',
            sender: PikiSender.agent,
            messageType: PikiMessageType.error,
          ),
        );
      }
    }
    _resetStatusAfterDelay(statusNotifier);
  }

  // ── ReAct Loop ─────────────────────────────────────────────────────────

  Future<bool> executeModelDrivenAgent(String text, PikiMode mode) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.thinking;

    final workNotes = <PikiWorkNote>[];
    _addWorkNote(
      workNotes,
      stage: 'planning',
      title: 'Planning request',
      detail:
          'Piki is deciding which grounded POS checks or actions are needed.',
    );

    var thinkingMsg = PikiMessage(
      content: 'Planning grounded steps...',
      sender: PikiSender.agent,
      messageType: PikiMessageType.thinking,
      attachedData: _workNotesAttachedData(workNotes),
    );
    _messagesNotifier.addMessage(thinkingMsg);

    PikiMessage? workingMsg;
    String currentPrompt = mode == PikiMode.advice
        ? '[ADVICE MODE]: $text\nPlease act as a Business Coach. Provide strategic advice, insights, and actionable recommendations based on the data.'
        : (mode == PikiMode.sell
              ? '[SELL MODE]: $text\nYou are acting as a cashier assistant. Your priority is to add items to the cart, adjust quantities, or checkout. Use the add_to_cart tool whenever the user mentions products or services.'
              : text);
    int loopCount = 0;
    int totalToolCalls = 0;
    final loopGuard = PikiAutoLoopGuard();
    final allResults = <Map<String, dynamic>>[];
    String finalAnswer = '';
    final List<String> suggestions = [];
    String? planSummary;
    String stopReason = 'completed';
    bool completed = false;
    bool needsUserInput = false;

    final plannerConversation = _conversationForPlanner();

    List<Map<String, dynamic>>? preSeededTools;
    if (mode == PikiMode.sell) {
      final command = PikiPosCommandEngine.parse(text);
      if (command.isKnown) {
        preSeededTools = [_toolCallForPosCommand(command)];
      }
    }

    try {
      while (loopGuard.canStartPlannerTurn(loopCount + 1)) {
        loopCount++;

        Map<String, dynamic> plan = {};
        List<Map<String, dynamic>> toolCalls = [];
        String modeValue = '';
        String? plannerAnswer;

        if (preSeededTools != null && loopCount == 1) {
          toolCalls = preSeededTools;
          modeValue = 'tool';
          _addWorkNote(
            workNotes,
            stage: 'planning',
            title: 'Recognized sell command',
            detail: _describeToolCalls(toolCalls),
            loop: loopCount,
          );
        } else {
          _addWorkNote(
            workNotes,
            stage: 'planning',
            title: 'Planning next step',
            detail:
                'Checking whether more POS data or local actions are needed.',
            loop: loopCount,
          );
          thinkingMsg = thinkingMsg.copyWith(
            content: 'Planning grounded steps...',
            attachedData: _workNotesAttachedData(workNotes),
          );
          _messagesNotifier.replaceMessage(thinkingMsg.id, thinkingMsg);

          plan = await OpenRouterService.planToolUse(
            userMessage: currentPrompt,
            conversation: plannerConversation,
            toolCatalog: PikiAgentService.toolCatalogPrompt(),
            memorySummary: _memorySummary(),
            includeBusinessContext:
                mode == PikiMode.plan ||
                mode == PikiMode.advice ||
                mode == PikiMode.sell,
          );

          modeValue = (plan['mode'] as String? ?? '').trim().toLowerCase();
          final normalized = _normalizeToolCalls(plan['tool_calls']);
          toolCalls = normalized.calls;
          plannerAnswer = (plan['answer'] as String?)?.trim();
          final currentPlanSummary = (plan['summary'] as String?)?.trim();
          planSummary ??= currentPlanSummary;

          if (toolCalls.isEmpty && normalized.skipped.isNotEmpty) {
            _lastPlannerError =
                'Tried to use invalid tools: ${normalized.skipped.join(', ')}';
            throw Exception(_lastPlannerError);
          }

          if (currentPlanSummary?.isNotEmpty == true) {
            _addWorkNote(
              workNotes,
              stage: 'planning',
              title: 'Plan summary',
              detail: currentPlanSummary!,
              loop: loopCount,
            );
          }

          if (plan.containsKey('suggestions')) {
            final s = plan['suggestions'];
            if (s is List) {
              suggestions.clear();
              suggestions.addAll(s.cast<String>());
            }
          }
        }

        if (toolCalls.isEmpty || modeValue == 'answer') {
          finalAnswer = plannerAnswer?.isNotEmpty == true
              ? plannerAnswer!
              : (allResults.isNotEmpty
                    ? 'I have completed the tasks.'
                    : 'I do not need a data lookup for that one.');
          needsUserInput =
              plannerAnswer != null &&
              _looksLikeUserInputRequest(plannerAnswer);
          completed = !needsUserInput;
          stopReason = needsUserInput ? 'needs_user_input' : 'completed';
          _addWorkNote(
            workNotes,
            stage: needsUserInput ? 'blocked' : 'done',
            title: needsUserInput ? 'Needs your input' : 'Final answer ready',
            detail: needsUserInput
                ? 'Piki needs more details before it can safely continue.'
                : 'Piki has enough information to answer.',
            loop: loopCount,
          );
          break;
        }

        final guardDecision = loopGuard.checkToolBatch(
          loopCount: loopCount,
          totalToolCalls: totalToolCalls,
          toolCalls: toolCalls,
        );
        if (guardDecision.shouldStop) {
          stopReason = guardDecision.reason ?? 'stopped_safely';
          _addWorkNote(
            workNotes,
            stage: 'blocked',
            title: 'Paused safely',
            detail:
                guardDecision.detail ?? 'Piki paused before repeating work.',
            loop: loopCount,
          );
          finalAnswer = _bestEffortAnswerFromResults(
            results: allResults,
            stopReason: guardDecision.detail ?? stopReason,
          );
          break;
        }

        _addWorkNote(
          workNotes,
          stage: 'tool',
          title: 'Running local tools',
          detail: _describeToolCalls(toolCalls),
          loop: loopCount,
        );

        final steps = toolCalls
            .map(
              (call) =>
                  PikiAgentService.buildStepForTool(call['tool'] as String),
            )
            .toList();

        thinkingMsg = thinkingMsg.copyWith(
          steps: steps,
          attachedData: _workNotesAttachedData(workNotes),
        );
        _messagesNotifier.replaceMessage(thinkingMsg.id, thinkingMsg);

        statusNotifier.state = AgentStatus.working;
        workingMsg = PikiMessage(
          content: 'Running local tools... 0 of ${toolCalls.length}',
          sender: PikiSender.agent,
          messageType: PikiMessageType.working,
          steps: List<PikiStep>.from(steps),
          attachedData: _workNotesAttachedData(workNotes),
        );
        _messagesNotifier.addMessage(workingMsg);

        final loopResults = <Map<String, dynamic>>[];
        var stopAfterToolError = false;
        for (int i = 0; i < toolCalls.length; i++) {
          final updatedSteps = _cloneSteps(workingMsg.steps!);
          for (int j = 0; j < i; j++) {
            updatedSteps[j] = updatedSteps[j].copyWith(
              status: PikiStepStatus.done,
            );
          }
          updatedSteps[i] = updatedSteps[i].copyWith(
            status: PikiStepStatus.working,
          );
          _messagesNotifier.replaceMessage(
            workingMsg.id,
            workingMsg.copyWith(
              steps: updatedSteps,
              content: 'Running local tools... ${i + 1} of ${toolCalls.length}',
              attachedData: _workNotesAttachedData(workNotes),
            ),
          );

          final call = toolCalls[i];
          final toolName = call['tool'] as String;
          final args =
              (call['arguments'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const <String, dynamic>{};

          final isCartTool =
              toolName == PikiAgentService.toolAddToCart ||
              toolName == PikiAgentService.toolRemoveFromCart ||
              toolName == PikiAgentService.toolSetCartQuantity ||
              toolName == PikiAgentService.toolRepeatLast ||
              toolName == PikiAgentService.toolClearCart ||
              toolName == PikiAgentService.toolCheckout ||
              toolName == PikiAgentService.toolHoldSale ||
              toolName == PikiAgentService.toolTeachAlias;

          Map<String, dynamic> result;
          totalToolCalls++;
          try {
            result = await (isCartTool
                ? _executeCartTool(toolName, args)
                : PikiAgentService.executeAgentTool(
                    toolName,
                    args: args,
                    memory: _lastToolResults,
                  ));
          } catch (e) {
            stopAfterToolError = true;
            stopReason = 'tool_error';
            result = {
              'tool': toolName,
              'success': false,
              'error': e.toString().replaceFirst('Exception: ', ''),
              'summary': 'Could not complete $toolName.',
            };
            _addWorkNote(
              workNotes,
              stage: 'error',
              title: 'Tool failed',
              detail: result['error'] as String,
              loop: loopCount,
            );
          }
          loopResults.add(result);

          if (result['action'] == 'checkout' || result['action'] == 'pos') {
            _ref.read(pikiNavigateProvider.notifier).state = PikiNavTarget.pos;
          }

          updatedSteps[i] = updatedSteps[i].copyWith(
            status: PikiStepStatus.done,
            result: result,
          );
          _messagesNotifier.replaceMessage(
            workingMsg.id,
            workingMsg.copyWith(
              steps: updatedSteps,
              attachedData: _workNotesAttachedData(workNotes),
            ),
          );
          _addWorkNote(
            workNotes,
            stage: result['error'] == null ? 'result' : 'error',
            title: result['error'] == null ? 'Tool finished' : 'Tool issue',
            detail: _resultSummary(result),
            loop: loopCount,
          );
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (stopAfterToolError) {
            break;
          }
        }
        allResults.addAll(loopResults);

        thinkingMsg = thinkingMsg.copyWith(
          steps: steps
              .map((step) => step.copyWith(status: PikiStepStatus.done))
              .toList(),
          content: 'Analyzing results...',
          attachedData: _workNotesAttachedData(workNotes),
        );
        _messagesNotifier.replaceMessage(thinkingMsg.id, thinkingMsg);

        _messagesNotifier.removeMessagesWhere((m) => m.id == workingMsg!.id);
        workingMsg = null;

        if (stopAfterToolError) {
          finalAnswer = _bestEffortAnswerFromResults(
            results: allResults,
            stopReason: 'a local tool failed',
          );
          break;
        }

        plannerConversation.add({'role': 'user', 'content': currentPrompt});
        plannerConversation.add({
          'role': 'assistant',
          'content': 'Executed tools with results:\n${jsonEncode(loopResults)}',
        });

        if (preSeededTools != null && loopCount == 1) {
          final result = loopResults.last;
          if (result['error'] == null) {
            finalAnswer = result['summary'] as String? ?? 'Done.';
            completed = true;
            stopReason = 'completed';
            _addWorkNote(
              workNotes,
              stage: 'done',
              title: 'Sell command completed',
              detail: _resultSummary(result),
              loop: loopCount,
            );
            break;
          } else {
            final errStr = result['error'].toString();
            if (!errStr.contains(
              'Could not find product or service matching',
            )) {
              finalAnswer = errStr;
              stopReason = 'tool_error';
              break;
            }
            // If it couldn't find the product, it might be a conversational query.
            // Let the loop continue so the LLM planner can handle it.
          }
        }

        _addWorkNote(
          workNotes,
          stage: 'analysis',
          title: 'Analyzing results',
          detail:
              'Piki is checking whether the request is complete or needs another action.',
          loop: loopCount,
        );

        currentPrompt =
            '''
Original request: $text

Tool Results:
${jsonEncode(loopResults)}

Analyze these results. If you have fully answered the original request, return mode="answer" and provide your final paragraph-style synthesis and business recommendations. If you need to perform more actions based on these results, return mode="tool" and provide the next tool_calls.
''';
        statusNotifier.state = AgentStatus.thinking;
      }

      if (finalAnswer.trim().isEmpty) {
        stopReason = 'max_planner_turns';
        finalAnswer = _bestEffortAnswerFromResults(
          results: allResults,
          stopReason: 'Piki reached the planning safety limit',
        );
        _addWorkNote(
          workNotes,
          stage: 'blocked',
          title: 'Paused safely',
          detail: 'Piki reached the planning safety limit.',
          loop: loopCount,
        );
      }

      if (finalAnswer.trim().isEmpty) {
        if (allResults.isEmpty) {
          finalAnswer =
              'I could not complete the plan for that request. Please try again with one specific action.';
        } else {
          final resultsStr = allResults
              .take(4)
              .map(
                (r) => '• ${r["summary"] ?? r["title"] ?? r["tool"] ?? "Done"}',
              )
              .join('\n');
          finalAnswer =
              'I completed the local checks, but could not finish the AI summary. Key results:\n$resultsStr';
        }
      }

      _messagesNotifier.removeMessagesWhere(
        (message) =>
            message.id == thinkingMsg.id || message.id == workingMsg?.id,
      );

      final citations = _collectCitations(allResults);

      PikiMessageType finalType = PikiMessageType.aiResponse;
      if (allResults.any((r) => r['type'] == 'chart')) {
        finalType = PikiMessageType.chart;
      }

      final runState = PikiRunState(
        loopCount: loopCount,
        toolCount: totalToolCalls,
        stopReason: stopReason,
        completed: completed || stopReason == 'completed',
        needsUserInput: needsUserInput,
      );

      _messagesNotifier.addMessage(
        PikiMessage(
          content: finalAnswer,
          sender: PikiSender.agent,
          messageType: finalType,
          attachedData: {
            'type': finalType == PikiMessageType.chart
                ? 'chart'
                : 'ai_response',
            'model': OpenRouterService.modelName,
            'citations': citations,
            'tool_results': allResults,
            'plan_summary': planSummary,
            'work_notes': workNotes.map((note) => note.toJson()).toList(),
            'run_state': runState.toJson(),
          },
          suggestions: suggestions.isNotEmpty ? suggestions : null,
        ),
      );

      rememberInteraction(
        userInput: text,
        reply: finalAnswer,
        tools: allResults
            .map((r) => r['tool'] as String? ?? '')
            .where((t) => t.isNotEmpty)
            .toList(),
        results: allResults,
      );
      if (allResults.isNotEmpty) {
        _ref.read(pikiInsightProvider.notifier).state = const PikiInsightData(
          text: 'Analyzing...',
        );
        PikiAgentService.generateInsight(allResults.first).then((insight) {
          _ref.read(pikiInsightProvider.notifier).state = insight;
        });
      }
      _resetStatusAfterDelay(statusNotifier);
      return true;
    } catch (e) {
      _lastPlannerError = e.toString().replaceFirst('Exception: ', '');
      _addWorkNote(
        workNotes,
        stage: 'error',
        title: 'Piki stopped',
        detail: _lastPlannerError!,
        loop: loopCount == 0 ? null : loopCount,
      );
      _messagesNotifier.removeMessagesWhere(
        (message) =>
            message.id == thinkingMsg.id || message.id == workingMsg?.id,
      );
      _messagesNotifier.addMessage(
        PikiMessage(
          content: 'I could not complete that request. $_lastPlannerError',
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
          attachedData: _workNotesAttachedData(
            workNotes,
            runState: PikiRunState(
              loopCount: loopCount,
              toolCount: totalToolCalls,
              stopReason: 'error',
              completed: false,
            ),
            type: 'error',
          ),
        ),
      );
      statusNotifier.state = AgentStatus.idle;
      return true;
    }
  }

  bool isPurchaseDraftConfirm(String text) {
    final lower = text.toLowerCase();
    return const [
      'confirm purchase draft',
      'confirm draft',
      'approve purchase draft',
      'create purchase draft',
      'create purchase now',
      'save purchase draft',
      'go ahead with purchase draft',
    ].any(lower.contains);
  }

  bool isPurchaseDraftCancel(String text) {
    final lower = text.toLowerCase();
    return const [
      'cancel purchase draft',
      'discard purchase draft',
      'reject purchase draft',
      'cancel draft',
      'discard draft',
    ].any(lower.contains);
  }

  void discardPendingPurchaseDraft(String userInput) {
    _pendingPurchaseDraft = null;
    final reply = 'Purchase draft discarded.';
    _messagesNotifier.addMessage(
      PikiMessage(
        content: reply,
        sender: PikiSender.agent,
        messageType: PikiMessageType.taskComplete,
      ),
    );
    rememberInteraction(
      userInput: userInput,
      reply: reply,
      tools: const ['purchase_draft_cancel'],
    );
  }

  Future<void> confirmPendingPurchaseDraft(String userInput) async {
    final draft = _pendingPurchaseDraft;
    if (draft == null) {
      const reply = 'There is no pending purchase draft to confirm.';
      _messagesNotifier.addMessage(
        PikiMessage(
          content: reply,
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      );
      rememberInteraction(userInput: userInput, reply: reply);
      return;
    }

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final details = <String>[];
    try {
      final rawItems =
          (draft['items'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          <Map<String, dynamic>>[];
      if (rawItems.isEmpty) {
        throw Exception('The pending purchase draft has no items.');
      }

      final grouped = <String, List<Map<String, dynamic>>>{};
      final supplierMeta = <String, Map<String, String?>>{};
      for (final item in rawItems) {
        final supplierId = (item['suggested_supplier_id'] as String?)?.trim();
        final supplierName = (item['suggested_supplier_name'] as String?)
            ?.trim();
        final groupKey = supplierId?.isNotEmpty == true
            ? 'id:$supplierId'
            : supplierName?.isNotEmpty == true
            ? 'name:$supplierName'
            : 'unspecified';
        grouped.putIfAbsent(groupKey, () => <Map<String, dynamic>>[]).add(item);
        supplierMeta[groupKey] = {
          'supplierId': supplierId,
          'supplierName': supplierName,
        };
      }

      final purchaseIds = <String>[];
      var totalLines = 0;
      for (final entry in grouped.entries) {
        final meta = supplierMeta[entry.key] ?? const <String, String?>{};
        final purchaseItems = entry.value
            .map(
              (item) => {
                'product_id': item['product_id'],
                'quantity': (item['recommended_qty'] as num? ?? 0).toDouble(),
                'unit_cost': (item['last_unit_cost'] as num? ?? 0).toDouble(),
                'unit': item['unit'],
              },
            )
            .where(
              (item) =>
                  (item['product_id'] as String?)?.isNotEmpty == true &&
                  ((item['quantity'] as double?) ?? 0) > 0,
            )
            .toList();
        if (purchaseItems.isEmpty) {
          continue;
        }
        totalLines += purchaseItems.length;
        final supplierName = meta['supplierName'];
        final purchaseId = await PurchaseRepository.createPurchase(
          supplierId: meta['supplierId'],
          supplierName: supplierName,
          note: supplierName?.isNotEmpty == true
              ? 'Created from confirmed Piki purchase draft for $supplierName.'
              : 'Created from confirmed Piki purchase draft.',
          items: purchaseItems,
        );
        purchaseIds.add(purchaseId);
        details.add(
          supplierName?.isNotEmpty == true
              ? 'Saved ${purchaseItems.length} line(s) for $supplierName'
              : 'Saved ${purchaseItems.length} line(s) as a purchase without supplier',
        );
      }

      if (purchaseIds.isEmpty) {
        throw Exception('No valid purchase lines were available to save.');
      }

      _pendingPurchaseDraft = null;
      final reply =
          'Purchase draft confirmed and saved as ${purchaseIds.length} purchase record(s).';
      _messagesNotifier.addMessage(
        PikiMessage(
          content: reply,
          sender: PikiSender.agent,
          messageType: PikiMessageType.taskComplete,
          attachedData: {
            'results': {
              'purchaseDraftConfirm': {
                'type': 'purchase_created',
                'purchase_ids': purchaseIds,
                'purchase_count': purchaseIds.length,
                'line_count': totalLines,
              },
            },
            'details': details,
            'skill_count': 1,
          },
        ),
      );
      rememberInteraction(
        userInput: userInput,
        reply: reply,
        tools: const ['purchase_draft_confirm'],
        results: [
          {
            'tool': 'purchase_draft_confirm',
            'type': 'purchase_created',
            'summary': reply,
          },
        ],
      );
    } catch (e) {
      final reply = 'Could not save the purchase draft: $e';
      _messagesNotifier.addMessage(
        PikiMessage(
          content: reply,
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      );
      rememberInteraction(userInput: userInput, reply: reply);
    }
    _resetStatusAfterDelay(statusNotifier);
  }

  // ── Cart / Sell Mode Tools ─────────────────────────────────────────────

  Map<String, dynamic> _toolCallForPosCommand(PikiPosCommand command) {
    switch (command.type) {
      case PikiPosCommandType.addItem:
        return {
          'tool': PikiAgentService.toolAddToCart,
          'reason': 'Fast path sell command',
          'arguments': {'query': command.query, 'qty': command.quantity ?? 1},
        };
      case PikiPosCommandType.removeItem:
        return {
          'tool': PikiAgentService.toolRemoveFromCart,
          'reason': 'Fast path remove command',
          'arguments': {'query': command.query, 'qty': command.quantity},
        };
      case PikiPosCommandType.setQuantity:
        return {
          'tool': PikiAgentService.toolSetCartQuantity,
          'reason': 'Fast path quantity command',
          'arguments': {'query': command.query, 'qty': command.quantity},
        };
      case PikiPosCommandType.repeatLast:
        return {
          'tool': PikiAgentService.toolRepeatLast,
          'reason': 'Fast path repeat command',
          'arguments': {'qty': command.quantity ?? 1},
        };
      case PikiPosCommandType.clearCart:
        return {
          'tool': PikiAgentService.toolClearCart,
          'reason': 'Fast path clear cart',
          'arguments': <String, dynamic>{},
        };
      case PikiPosCommandType.checkout:
        return {
          'tool': PikiAgentService.toolCheckout,
          'reason': 'Fast path checkout',
          'arguments': {'payment_type': command.paymentType},
        };
      case PikiPosCommandType.holdSale:
        return {
          'tool': PikiAgentService.toolHoldSale,
          'reason': 'Fast path hold sale',
          'arguments': <String, dynamic>{},
        };
      case PikiPosCommandType.teachAlias:
        return {
          'tool': PikiAgentService.toolTeachAlias,
          'reason': 'Fast path cashier learning',
          'arguments': {'alias': command.alias, 'target': command.target},
        };
      case PikiPosCommandType.unknown:
        return {
          'tool': PikiAgentService.toolAddToCart,
          'reason': 'Fallback sell command',
          'arguments': {'query': command.query, 'qty': command.quantity ?? 1},
        };
    }
  }

  Future<Map<String, dynamic>> _executeCartTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    switch (tool) {
      case PikiAgentService.toolAddToCart:
        return _addToCart(args);
      case PikiAgentService.toolRemoveFromCart:
        return _removeFromCart(args);
      case PikiAgentService.toolSetCartQuantity:
        return _setCartQuantity(args);
      case PikiAgentService.toolRepeatLast:
        return _repeatLast(args);
      case PikiAgentService.toolClearCart:
        return _clearCart();
      case PikiAgentService.toolCheckout:
        return _checkout();
      case PikiAgentService.toolHoldSale:
        return _holdSale();
      case PikiAgentService.toolTeachAlias:
        return _teachAlias(args);
      default:
        throw Exception('Unknown cart tool: $tool');
    }
  }

  Future<Map<String, dynamic>> _addToCart(Map<String, dynamic> args) async {
    final query = (args['query'] as String?)?.trim();
    final qty = _coercePositiveDouble(args['qty'] ?? args['quantity'], 1);

    if (query == null || query.isEmpty) {
      return {'error': 'No product specified in query.'};
    }

    final sellable = await PikiAgentService.findSellableProductForSale(
      query,
      aliases: _posAliases,
    );
    final resolvedQuery = PikiAgentService.resolveSaleAlias(query, _posAliases);
    final service = sellable == null
        ? await PikiAgentService.findServiceForSale(resolvedQuery)
        : null;

    if (sellable == null && service == null) {
      return {
        'error':
            'Could not find product or service matching "$query". Check spelling or inventory.',
      };
    }

    final cartNotifier = _ref.read(cartProvider.notifier);
    final currency = ShopSettings.currency;

    if (sellable != null) {
      final product = sellable.product;
      final variant = sellable.variant;
      final cartKey = sellable.cartKey;
      final previousItem = _cartItemByKey(cartKey);
      final previousQty = previousItem?.quantity ?? 0;
      final added = cartNotifier.addProduct(product, variant: variant);
      var adjustedToAvailable = false;

      if (!added) {
        final stockSource = variant ?? product;
        final stock = (stockSource['stock'] as num? ?? 0).toDouble();
        return {
          'error':
              '${sellable.label} is out of stock (${_qtyLabel(stock)} available).',
        };
      }

      final desiredQty = previousQty + qty;
      var accepted = cartNotifier.setQuantity(cartKey, desiredQty);
      if (!accepted) {
        final item = _cartItemByKey(cartKey);
        final availableQty = item?.maxStock ?? 0;
        if (availableQty > previousQty) {
          cartNotifier.setQuantity(cartKey, availableQty);
          adjustedToAvailable = true;
          accepted = true;
        }
      }
      if (!accepted) {
        return {
          'error':
              'Could not add more ${sellable.label}; it is already at the available stock limit.',
        };
      }

      final item = _cartItemByKey(cartKey);
      final actualQty = item?.quantity ?? desiredQty;
      final addedQty = actualQty - previousQty;
      final total = (item?.unitPrice ?? 0) * actualQty;
      final unit = item?.unit ?? (product['unit'] as String? ?? 'pcs');
      _lastSellQuery = query;
      _lastCartKey = cartKey;
      _lastCartLabel = sellable.label;
      await _persistPosMemory();

      return {
        'summary': adjustedToAvailable
            ? 'Only ${_qtyLabel(actualQty)} $unit available. Cart line is now ${_qtyLabel(actualQty)} x ${sellable.label} -> $currency${total.toStringAsFixed(2)}'
            : 'Added ${_qtyLabel(addedQty)} x ${sellable.label}. Cart line is now ${_qtyLabel(actualQty)} -> $currency${total.toStringAsFixed(2)}',
        'type': 'cart_item_added',
        'product_name': sellable.label,
        'variant_id': variant?['id'],
        'cart_key': cartKey,
        'qty': actualQty,
        'added_qty': addedQty,
        'price': item?.unitPrice,
        'total': total,
      };
    } else if (service != null) {
      final price = (service['base_price'] as num? ?? 0).toDouble();
      final serviceQty = qty.ceil();
      var ordersCreated = 0;
      final orderIds = <String>[];

      try {
        for (int i = 0; i < serviceQty; i++) {
          final orderId = await ServiceRepository.createOrder(
            serviceId: service['id'] as String,
            serviceName: service['name'] as String,
            entryMode: 'walk_in',
            status: 'booked',
            assignedStaff: ServiceRepository.defaultAssignedStaffName(),
            assignedStaffUserId:
                ServiceRepository.currentAssignedStaffUserIdFor(
                  ServiceRepository.defaultAssignedStaffName(),
                ),
            price: price,
            note: 'Generated by Piki Assistant in Sell Mode',
          );
          orderIds.add(orderId);
          final added = cartNotifier.addService(
            serviceOrderId: orderId,
            serviceId: service['id'] as String,
            serviceName: service['name'] as String,
            price: price,
          );
          if (added) ordersCreated++;
        }

        final total = price * ordersCreated;
        if (orderIds.isNotEmpty) {
          _lastSellQuery = query;
          _lastCartKey = 'service:${orderIds.last}';
          _lastCartLabel = service['name'] as String?;
          await _persistPosMemory();
        }
        return {
          'summary':
              'Added $ordersCreated x ${service["name"]} (Service) -> $currency${total.toStringAsFixed(2)}',
          'type': 'cart_service_added',
          'service_name': service['name'],
          'qty': ordersCreated,
          'price': price,
          'total': total,
        };
      } catch (e) {
        return {'error': 'Could not create service order: $e'};
      }
    }

    return {'error': 'Unexpected error adding to cart.'};
  }

  Future<Map<String, dynamic>> _removeFromCart(
    Map<String, dynamic> args,
  ) async {
    final query = (args['query'] as String?)?.trim();
    final qty = _coercePositiveDouble(args['qty'] ?? args['quantity'], 0);
    final item = _findCartItem(query);
    if (item == null) {
      return {'error': 'I could not find that item in the cart.'};
    }

    final cartNotifier = _ref.read(cartProvider.notifier);
    if (qty <= 0 || qty >= item.quantity) {
      cartNotifier.removeProduct(item.cartKey);
      if (_lastCartKey == item.cartKey) {
        _lastCartKey = null;
        _lastCartLabel = null;
      }
      await _persistPosMemory();
      return {
        'summary': 'Removed ${_cartItemLabel(item)} from the cart.',
        'type': 'cart_item_removed',
        'cart_key': item.cartKey,
      };
    }

    final nextQty = item.quantity - qty;
    cartNotifier.setQuantity(item.cartKey, nextQty);
    _lastCartKey = item.cartKey;
    _lastCartLabel = _cartItemLabel(item);
    await _persistPosMemory();
    return {
      'summary':
          'Removed ${_qtyLabel(qty)} x ${_cartItemLabel(item)}. Quantity is now ${_qtyLabel(nextQty)}.',
      'type': 'cart_item_quantity_reduced',
      'cart_key': item.cartKey,
      'qty': nextQty,
    };
  }

  Future<Map<String, dynamic>> _setCartQuantity(
    Map<String, dynamic> args,
  ) async {
    final query = (args['query'] as String?)?.trim();
    final qty = _coercePositiveDouble(args['qty'] ?? args['quantity'], 0);
    if (qty <= 0) {
      return {'error': 'Quantity must be greater than zero.'};
    }
    final item = _findCartItem(query);
    if (item == null) {
      return {'error': 'I could not find that item in the cart.'};
    }

    final accepted = _ref
        .read(cartProvider.notifier)
        .setQuantity(item.cartKey, qty);
    if (!accepted) {
      return {
        'error':
            'Only ${_qtyLabel(item.maxStock)} ${item.unit} available for ${_cartItemLabel(item)}.',
      };
    }
    _lastCartKey = item.cartKey;
    _lastCartLabel = _cartItemLabel(item);
    await _persistPosMemory();
    return {
      'summary':
          'Set ${_cartItemLabel(item)} to ${_qtyLabel(qty)} ${item.unit}.',
      'type': 'cart_item_quantity_set',
      'cart_key': item.cartKey,
      'qty': qty,
    };
  }

  Future<Map<String, dynamic>> _repeatLast(Map<String, dynamic> args) async {
    if (_lastSellQuery == null || _lastSellQuery!.trim().isEmpty) {
      return {'error': 'I do not have a previous item to repeat yet.'};
    }
    final qty = _coercePositiveDouble(args['qty'] ?? args['quantity'], 1);
    return _addToCart({'query': _lastSellQuery, 'qty': qty});
  }

  Future<Map<String, dynamic>> _clearCart() async {
    _ref.read(cartProvider.notifier).clear();
    _lastCartKey = null;
    _lastCartLabel = null;
    await _persistPosMemory();
    return {'summary': 'Cart has been cleared.'};
  }

  Future<Map<String, dynamic>> _checkout() async {
    final cart = _ref.read(cartProvider);
    if (cart.isEmpty) {
      return {'error': 'Cart is empty. Please add items before checking out.'};
    }
    return {
      'action': 'checkout',
      'summary':
          'Navigating to POS screen for checkout with ${cart.length} item(s).',
    };
  }

  Future<Map<String, dynamic>> _holdSale() async {
    final cart = _ref.read(cartProvider);
    if (cart.isEmpty) {
      return {'error': 'Cart is empty. Add items before holding the sale.'};
    }
    final holdId = await HeldSaleRepository.createHold(
      name: 'Piki hold ${DateTime.now().toIso8601String().substring(11, 16)}',
      subtotal: _ref.read(cartSubtotalProvider),
      tax: _ref.read(cartTaxProvider),
      discount: _ref.read(discountProvider),
      total: _ref.read(cartTotalProvider),
      userId: SessionService.currentUserId.isNotEmpty
          ? SessionService.currentUserId
          : 'admin',
      cashierName: SessionService.currentUserName,
      items: cart.map((item) => item.toHeldItem()).toList(),
    );
    _ref.read(cartProvider.notifier).clear();
    _ref.read(discountProvider.notifier).state = 0;
    _ref.invalidate(heldSalesProvider);
    _lastCartKey = null;
    _lastCartLabel = null;
    await _persistPosMemory();
    return {
      'summary':
          'Held this sale with ${cart.length} item(s). The cart is ready for the next customer.',
      'type': 'held_sale_created',
      'id': holdId,
      'action': 'pos',
    };
  }

  Future<Map<String, dynamic>> _teachAlias(Map<String, dynamic> args) async {
    final alias = (args['alias'] as String?)?.trim().toLowerCase();
    final target = (args['target'] as String?)?.trim().toLowerCase();
    if (alias == null || alias.isEmpty || target == null || target.isEmpty) {
      return {'error': 'Tell me the phrase and what product it should mean.'};
    }
    _posAliases[alias] = target;
    await _persistPosMemory();
    unawaited(PikiProactiveService.syncAlias(alias: alias, target: target));
    return {
      'summary': 'Learned "$alias" means "$target" for cashier commands.',
      'type': 'pos_alias_learned',
      'alias': alias,
      'target': target,
    };
  }

  CartItem? _cartItemByKey(String cartKey) {
    for (final item in _ref.read(cartProvider)) {
      if (item.cartKey == cartKey) return item;
    }
    return null;
  }

  CartItem? _findCartItem(String? rawQuery) {
    final cart = _ref.read(cartProvider);
    if (cart.isEmpty) return null;

    final query = PikiAgentService.resolveSaleAlias(
      rawQuery?.trim() ?? '',
      _posAliases,
    );
    if (query.isEmpty) {
      return _lastCartKey == null ? cart.last : _cartItemByKey(_lastCartKey!);
    }

    final clean = _normalizeForMatch(query);
    for (final item in cart) {
      if (_cartCandidates(item).any((candidate) => candidate == clean)) {
        return item;
      }
    }
    for (final item in cart) {
      if (_cartCandidates(item).any(
        (candidate) => candidate.contains(clean) || clean.contains(candidate),
      )) {
        return item;
      }
    }
    return null;
  }

  Iterable<String> _cartCandidates(CartItem item) sync* {
    yield _normalizeForMatch(item.cartKey);
    yield _normalizeForMatch(item.productName);
    if (item.variantName != null) {
      yield _normalizeForMatch(item.variantName!);
      yield _normalizeForMatch('${item.productName} ${item.variantName}');
    }
  }

  String _cartItemLabel(CartItem item) {
    final variantName = item.variantName;
    if (variantName == null || variantName.trim().isEmpty) {
      return item.productName;
    }
    return '${item.productName} - $variantName';
  }

  String _normalizeForMatch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _qtyLabel(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double _coercePositiveDouble(dynamic value, double fallback) {
    final parsed = switch (value) {
      int _ => value.toDouble(),
      num _ => value.toDouble(),
      String _ => double.tryParse(value),
      _ => null,
    };
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }
}
