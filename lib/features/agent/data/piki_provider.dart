import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/openrouter_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../sales/data/cart_provider.dart';
import 'piki_agent_service.dart';
import 'piki_models.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final pikiModeProvider = StateProvider<PikiMode>((ref) => PikiMode.plan);

final pikiStatusProvider =
    StateProvider<AgentStatus>((ref) => AgentStatus.idle);

final pikiInsightProvider = StateProvider<String?>((ref) => null);

/// Navigation signal — avoids circular import with app_shell.dart.
enum PikiNavTarget { none, pos }
final pikiNavigateProvider =
    StateProvider<PikiNavTarget>((ref) => PikiNavTarget.none);

final pikiMessagesProvider =
    StateNotifierProvider<PikiMessagesNotifier, List<PikiMessage>>(
  (ref) => PikiMessagesNotifier(ref),
);

// ─── Notifier ────────────────────────────────────────────────────────────────

class PikiMessagesNotifier extends StateNotifier<List<PikiMessage>> {
  final Ref _ref;
  final List<Map<String, dynamic>> _memoryTurns = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _lastToolResults =
      <String, Map<String, dynamic>>{};
  Map<String, dynamic>? _pendingPurchaseDraft;

  PikiMessagesNotifier(this._ref) : super([]);

  // ── Public API ─────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // User bubble
    state = [
      ...state,
      PikiMessage(content: trimmed, sender: PikiSender.user),
    ];

    final mode = _ref.read(pikiModeProvider);

    if (mode == PikiMode.sell) {
      await _executeSellMode(trimmed);
      return;
    }

    if (_pendingPurchaseDraft != null && _isPurchaseDraftCancel(trimmed)) {
      _discardPendingPurchaseDraft(trimmed);
      return;
    }
    if (_pendingPurchaseDraft != null && _isPurchaseDraftConfirm(trimmed)) {
      await _confirmPendingPurchaseDraft(trimmed);
      return;
    }

    var aiEnabled = OpenRouterService.isEnabled;
    if (!aiEnabled) {
      aiEnabled = await OpenRouterService.refreshConfig();
    }
    if (aiEnabled) {
      final handled = await _executeModelDrivenAgent(trimmed, mode);
      if (handled) {
        return;
      }
    }

    final skills = PikiAgentService.matchSkills(trimmed);

    if (skills.isEmpty) {
      if (aiEnabled) {
        await _executeAiChat(trimmed, mode);
        return;
      }
      state = [
        ...state,
        PikiMessage(
          content:
              "I'm not sure how to help with that yet. Try asking me to:\n"
              '• Check low stock\n'
              "• Show today's summary\n"
              '• Create a restock list\n'
              '• Show recent sales\n'
              '• Check expiring products\n'
              '• Show profit or shift summary\n'
              '• Show top debtors, top products, or expenses\n'
              '\nOr switch to Sell Mode to ring up items!',
          sender: PikiSender.agent,
        ),
      ];
      return;
    }

    if (mode == PikiMode.plan) {
      await _executePlanMode(skills);
    } else {
      await _executeFastMode(skills);
    }
  }

  void executeQuickAction(String action) => sendMessage(action);

  // ── Plan mode ──────────────────────────────────────────────────────────

  Future<void> _executePlanMode(List<PikiSkill> skills) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.thinking;

    final steps = PikiAgentService.buildSteps(skills);

    // Thinking bubble
    final thinkingMsg = PikiMessage(
      content: 'Thinking...',
      sender: PikiSender.agent,
      messageType: PikiMessageType.thinking,
      steps: steps,
    );
    state = [...state, thinkingMsg];
    await Future<void>.delayed(const Duration(milliseconds: 900));

    // Working bubble
    statusNotifier.state = AgentStatus.working;
    final workingMsg = PikiMessage(
      content: 'Completing tasks... 0 of ${skills.length}',
      sender: PikiSender.agent,
      messageType: PikiMessageType.working,
      steps: List<PikiStep>.from(steps),
    );
    state = [...state, workingMsg];

    final allResults = <String, dynamic>{};
    final completedDetails = <String>[];

    for (int i = 0; i < skills.length; i++) {
      // Mark current step as working
      final updatedSteps = _cloneSteps(workingMsg.steps!);
      for (int j = 0; j < i; j++) {
        updatedSteps[j] = updatedSteps[j].copyWith(status: PikiStepStatus.done);
      }
      updatedSteps[i] =
          updatedSteps[i].copyWith(status: PikiStepStatus.working);

      _replaceMessage(
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
        _replaceMessage(
          workingMsg.id,
          workingMsg.copyWith(steps: updatedSteps),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } catch (e) {
        updatedSteps[i] =
            updatedSteps[i].copyWith(status: PikiStepStatus.error);
        completedDetails.add('Error: $e');
      }
    }

    // Mark all thinking steps as done
    _replaceMessage(
      thinkingMsg.id,
      thinkingMsg.copyWith(
        steps: steps.map((s) => s.copyWith(status: PikiStepStatus.done)).toList(),
      ),
    );

    // Task-complete bubble
    state = [
      ...state,
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
    ];

    _publishInsightFromResults(allResults);
    _resetStatusAfterDelay(statusNotifier);
  }

  // ── Fast mode ──────────────────────────────────────────────────────────

  Future<void> _executeFastMode(List<PikiSkill> skills) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;

    for (final skill in skills) {
      try {
        final result = await PikiAgentService.executeSkill(skill);
        final hasItems = ((result['items'] as List?)?.isNotEmpty ?? false);

        state = [
          ...state,
          PikiMessage(
            content: result['summary'] as String? ?? 'Done',
            sender: PikiSender.agent,
            messageType:
                hasItems ? PikiMessageType.productCard : PikiMessageType.taskComplete,
            attachedData: result,
          ),
        ];

        _ref.read(pikiInsightProvider.notifier).state =
            PikiAgentService.generateInsight(result);
      } catch (e) {
        state = [
          ...state,
          PikiMessage(
            content: 'Error: $e',
            sender: PikiSender.agent,
            messageType: PikiMessageType.error,
          ),
        ];
      }
    }

    _resetStatusAfterDelay(statusNotifier);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _replaceMessage(String id, PikiMessage updated) {
    state = state.map((m) => m.id == id ? updated : m).toList();
  }

  List<PikiStep> _cloneSteps(List<PikiStep> source) =>
      source.map((s) => PikiStep(
        label: s.label,
        description: s.description,
        icon: s.icon,
        status: s.status,
        result: s.result,
      )).toList();

  void _publishInsightFromResults(Map<String, dynamic> allResults) {
    if (allResults.isEmpty) return;
    final first = allResults.values.first;
    if (first is Map<String, dynamic>) {
      _ref.read(pikiInsightProvider.notifier).state =
          PikiAgentService.generateInsight(first);
    }
  }

  List<Map<String, String>> _conversationForPlanner() {
    final messages = state
        .where((message) =>
            message.messageType != PikiMessageType.thinking &&
            message.messageType != PikiMessageType.working)
        .toList();
    final slice = messages.length > 8
        ? messages.sublist(messages.length - 8)
        : messages;
    return slice
        .map((message) => {
              'role': message.sender == PikiSender.user ? 'user' : 'assistant',
              'content': message.content,
            })
        .toList();
  }

  String _memorySummary() {
    if (_memoryTurns.isEmpty && _lastToolResults.isEmpty) {
      return 'No follow-up memory yet.';
    }
    final lines = <String>[];
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
        lines.add(
          '- ${entry.key}: ${entry.value['summary'] ?? entry.value['title'] ?? 'available'}',
        );
      }
    }
    return lines.join('\n');
  }

  void _rememberInteraction({
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
  }

  bool _isPurchaseDraftConfirm(String text) {
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

  bool _isPurchaseDraftCancel(String text) {
    final lower = text.toLowerCase();
    return const [
      'cancel purchase draft',
      'discard purchase draft',
      'reject purchase draft',
      'cancel draft',
      'discard draft',
    ].any(lower.contains);
  }

  List<Map<String, dynamic>> _normalizeToolCalls(dynamic rawToolCalls) {
    if (rawToolCalls is! List) {
      return const <Map<String, dynamic>>[];
    }
    return rawToolCalls
        .whereType<Map>()
        .map((call) => Map<String, dynamic>.from(call))
        .where((call) => (call['tool'] as String?)?.trim().isNotEmpty == true)
        .toList();
  }

  List<Map<String, dynamic>> _collectCitations(
    List<Map<String, dynamic>> results,
  ) {
    final citations = <Map<String, dynamic>>[];
    var index = 1;
    for (final result in results) {
      final resultCitations =
          (result['citations'] as List?)?.whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
              ) ??
              const Iterable<Map<String, dynamic>>.empty();
      for (final citation in resultCitations) {
        citations.add({
          'index': index,
          'tool': result['tool'],
          ...citation,
        });
        index += 1;
      }
    }
    return citations;
  }

  void _resetStatusAfterDelay(StateController<AgentStatus> notifier) {
    notifier.state = AgentStatus.completed;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (_ref.read(pikiStatusProvider) == AgentStatus.completed) {
        notifier.state = AgentStatus.idle;
      }
    });
  }

  void _discardPendingPurchaseDraft(String userInput) {
    _pendingPurchaseDraft = null;
    const reply = 'Purchase draft discarded. No purchases were created.';
    state = [
      ...state,
      PikiMessage(
        content: reply,
        sender: PikiSender.agent,
        messageType: PikiMessageType.taskComplete,
      ),
    ];
    _rememberInteraction(userInput: userInput, reply: reply);
  }

  Future<void> _confirmPendingPurchaseDraft(String userInput) async {
    final draft = _pendingPurchaseDraft;
    if (draft == null) {
      const reply = 'There is no pending purchase draft to confirm.';
      state = [
        ...state,
        PikiMessage(
          content: reply,
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      ];
      _rememberInteraction(userInput: userInput, reply: reply);
      return;
    }

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final details = <String>[];
    try {
      final rawItems = (draft['items'] as List?)
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
        final supplierName =
            (item['suggested_supplier_name'] as String?)?.trim();
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
            .map((item) => {
                  'product_id': item['product_id'],
                  'quantity': (item['recommended_qty'] as num? ?? 0).toDouble(),
                  'unit_cost': (item['last_unit_cost'] as num? ?? 0).toDouble(),
                  'unit': item['unit'],
                })
            .where((item) =>
                (item['product_id'] as String?)?.isNotEmpty == true &&
                ((item['quantity'] as double?) ?? 0) > 0)
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
      state = [
        ...state,
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
      ];
      _rememberInteraction(
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
      state = [
        ...state,
        PikiMessage(
          content: reply,
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      ];
      _rememberInteraction(userInput: userInput, reply: reply);
    }
    _resetStatusAfterDelay(statusNotifier);
  }

  Future<bool> _executeModelDrivenAgent(String text, PikiMode mode) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.thinking;

    final thinkingMsg = PikiMessage(
      content: 'Planning grounded steps...',
      sender: PikiSender.agent,
      messageType: PikiMessageType.thinking,
    );
    state = [...state, thinkingMsg];

    PikiMessage? workingMsg;
    try {
      final plan = await OpenRouterService.planToolUse(
        userMessage: text,
        conversation: _conversationForPlanner(),
        toolCatalog: PikiAgentService.toolCatalogPrompt(),
        memorySummary: _memorySummary(),
        includeBusinessContext: mode == PikiMode.plan,
      );

      final modeValue = (plan['mode'] as String? ?? '').trim().toLowerCase();
      final toolCalls = _normalizeToolCalls(plan['tool_calls']);
      final plannerAnswer = (plan['answer'] as String?)?.trim();

      if (toolCalls.isEmpty || modeValue == 'answer') {
        state = state.where((message) => message.id != thinkingMsg.id).toList();
        final reply = plannerAnswer?.isNotEmpty == true
            ? plannerAnswer!
            : 'I do not need a data lookup for that one.';
        state = [
          ...state,
          PikiMessage(
            content: reply,
            sender: PikiSender.agent,
            messageType: PikiMessageType.aiResponse,
            attachedData: {
              'type': 'ai_response',
              'model': OpenRouterService.modelName,
              'citations': const <Map<String, dynamic>>[],
            },
          ),
        ];
        _rememberInteraction(userInput: text, reply: reply);
        _resetStatusAfterDelay(statusNotifier);
        return true;
      }

      final steps = toolCalls
          .map((call) => PikiAgentService.buildStepForTool(call['tool'] as String))
          .toList();
      _replaceMessage(
        thinkingMsg.id,
        thinkingMsg.copyWith(steps: steps),
      );

      statusNotifier.state = AgentStatus.working;
      workingMsg = PikiMessage(
        content: 'Running local tools... 0 of ${toolCalls.length}',
        sender: PikiSender.agent,
        messageType: PikiMessageType.working,
        steps: List<PikiStep>.from(steps),
      );
      state = [...state, workingMsg];

      final results = <Map<String, dynamic>>[];
      for (int i = 0; i < toolCalls.length; i++) {
        final updatedSteps = _cloneSteps(workingMsg.steps!);
        for (int j = 0; j < i; j++) {
          updatedSteps[j] = updatedSteps[j].copyWith(status: PikiStepStatus.done);
        }
        updatedSteps[i] = updatedSteps[i].copyWith(status: PikiStepStatus.working);
        _replaceMessage(
          workingMsg.id,
          workingMsg.copyWith(
            steps: updatedSteps,
            content: 'Running local tools... ${i + 1} of ${toolCalls.length}',
          ),
        );

        final call = toolCalls[i];
        final result = await PikiAgentService.executeAgentTool(
          call['tool'] as String,
          args: (call['arguments'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const <String, dynamic>{},
          memory: _lastToolResults,
        );
        results.add(result);
        updatedSteps[i] = updatedSteps[i].copyWith(
          status: PikiStepStatus.done,
          result: result,
        );
        _replaceMessage(
          workingMsg.id,
          workingMsg.copyWith(steps: updatedSteps),
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      _replaceMessage(
        thinkingMsg.id,
        thinkingMsg.copyWith(
          steps: steps.map((step) => step.copyWith(status: PikiStepStatus.done)).toList(),
        ),
      );

      final reply = PikiAgentService.composeGroundedReply(
        userInput: text,
        results: results,
      );
      final citations = _collectCitations(results);
      state = [
        ...state,
        PikiMessage(
          content: reply,
          sender: PikiSender.agent,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': 'ai_response',
            'model': OpenRouterService.modelName,
            'citations': citations,
            'tool_results': results,
            'plan_summary': plan['summary'],
          },
        ),
      ];

      _rememberInteraction(
        userInput: text,
        reply: reply,
        tools: toolCalls
            .map((call) => (call['tool'] as String?) ?? '')
            .where((tool) => tool.isNotEmpty)
            .toList(),
        results: results,
      );
      if (results.isNotEmpty) {
        _ref.read(pikiInsightProvider.notifier).state =
            PikiAgentService.generateInsight(results.first);
      }
      _resetStatusAfterDelay(statusNotifier);
      return true;
    } catch (_) {
      state = state
          .where(
            (message) =>
                message.id != thinkingMsg.id &&
                message.id != workingMsg?.id,
          )
          .toList();
      statusNotifier.state = AgentStatus.idle;
      return false;
    }
  }

  // ── Sell Mode ──────────────────────────────────────────────────────────

  Future<void> _executeSellMode(String text) async {
    // Cart-clear command
    if (PikiAgentService.isClearCartCommand(text)) {
      _ref.read(cartProvider.notifier).clear();
      state = [
        ...state,
        PikiMessage(
          content: 'Cart cleared. Ready for new items!',
          sender: PikiSender.agent,
          messageType: PikiMessageType.taskComplete,
        ),
      ];
      return;
    }

    // Checkout / go-to-POS command
    if (PikiAgentService.isCheckoutCommand(text)) {
      final cart = _ref.read(cartProvider);
      if (cart.isEmpty) {
        state = [
          ...state,
          PikiMessage(
            content: 'Your cart is empty. Add items first!',
            sender: PikiSender.agent,
            messageType: PikiMessageType.error,
          ),
        ];
        return;
      }
      state = [
        ...state,
        PikiMessage(
          content: 'Heading to POS with ${cart.length} item(s) ready for checkout...',
          sender: PikiSender.agent,
          messageType: PikiMessageType.taskComplete,
        ),
      ];
      // Signal navigation (avoids circular import with app_shell)
      _ref.read(pikiNavigateProvider.notifier).state = PikiNavTarget.pos;
      return;
    }

    // Parse sell intent
    final intent = PikiAgentService.parseSellIntent(text);
    if (intent == null) {
      state = [
        ...state,
        PikiMessage(
          content:
              'In Sell Mode, try:\n'
              '• "2 Coca Cola" — add 2 of an item\n'
              '• "sell 1 bread" — explicit verb\n'
              '• "checkout" — go to POS to pay\n'
              '• "clear cart" — empty the cart',
          sender: PikiSender.agent,
        ),
      ];
      return;
    }

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;

    final product = await PikiAgentService.findProductForSale(intent.query);

    if (product == null) {
      state = [
        ...state,
        PikiMessage(
          content:
              'No product found matching "${intent.query}". '
              'Check the spelling or search inventory.',
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      ];
      _resetStatusAfterDelay(statusNotifier);
      return;
    }

    final cartNotifier = _ref.read(cartProvider.notifier);
    final added = cartNotifier.addProduct(product);

    if (added && intent.qty > 1) {
      cartNotifier.setQuantity(product['id'] as String, intent.qty);
    }

    if (!added) {
      final stock = (product['stock'] as num? ?? 0).toDouble();
      state = [
        ...state,
        PikiMessage(
          content: '${product['name']} is out of stock '
              '(${stock.toStringAsFixed(0)} available).',
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      ];
    } else {
      final currency = ShopSettings.currency;
      final price = (product['price'] as num? ?? 0).toDouble();
      final total = price * intent.qty;
      final qtyStr = intent.qty == intent.qty.roundToDouble()
          ? intent.qty.toInt().toString()
          : intent.qty.toStringAsFixed(1);
      state = [
        ...state,
        PikiMessage(
          content:
              '✅ Added $qtyStr × ${product['name']}  →  '
              '$currency${total.toStringAsFixed(2)}',
          sender: PikiSender.agent,
          messageType: PikiMessageType.taskComplete,
          attachedData: {
            'type': 'cart_item_added',
            'product_name': product['name'],
            'qty': intent.qty,
            'price': price,
            'total': total,
          },
        ),
      ];
    }

    _resetStatusAfterDelay(statusNotifier);
  }

  // ── AI Chat (OpenRouter) ──────────────────────────────────────────────

  Future<void> _executeAiChat(String text, PikiMode mode) async {
    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.thinking;

    // Show thinking indicator
    state = [
      ...state,
      PikiMessage(
        content: 'Thinking...',
        sender: PikiSender.agent,
        messageType: PikiMessageType.thinking,
      ),
    ];

    try {
      // Build conversation history (last 10 messages for context)
      final recentMessages = state
          .where((m) =>
              m.messageType != PikiMessageType.thinking &&
              m.messageType != PikiMessageType.working)
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
        includeBusinessContext: mode == PikiMode.plan,
      );

      // Remove the thinking message and add the real response
      final withoutThinking = state
          .where((m) => m.messageType != PikiMessageType.thinking)
          .toList();

      state = [
        ...withoutThinking,
        PikiMessage(
          content: response,
          sender: PikiSender.agent,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': 'ai_response',
            'model': OpenRouterService.modelName,
          },
        ),
      ];
      _rememberInteraction(userInput: text, reply: response);
    } catch (e) {
      // Remove thinking message and show error
      final withoutThinking = state
          .where((m) => m.messageType != PikiMessageType.thinking)
          .toList();

      state = [
        ...withoutThinking,
        PikiMessage(
          content: '$e',
          sender: PikiSender.agent,
          messageType: PikiMessageType.error,
        ),
      ];
    }

    _resetStatusAfterDelay(statusNotifier);
  }
}
