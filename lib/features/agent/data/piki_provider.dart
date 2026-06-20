import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/services/openrouter_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/utils/error_messages.dart';
import '../../customers/data/customer_import_service.dart';
import '../../products/data/product_import_service.dart';
import '../../reports/data/expense_import_service.dart';
import '../../sales/data/sale_import_service.dart';
import 'piki_agent_service.dart';
import 'piki_brain_service.dart';
import 'piki_chat_repository.dart';
import 'piki_memory_service.dart';
import 'piki_models.dart';
import 'piki_proactive_service.dart';

enum PikiSmartImportTarget { products, sales, customers, expenses }

class PikiSmartImportDraft {
  final PikiSmartImportTarget target;
  final SpreadsheetImportPlan plan;
  final String fileName;

  const PikiSmartImportDraft({
    required this.target,
    required this.plan,
    required this.fileName,
  });
}

class _SmartImportResult {
  final PikiSmartImportTarget target;
  final Object result;

  const _SmartImportResult({required this.target, required this.result});
}

class _SmartTargetCandidate {
  final PikiSmartImportTarget target;
  final SpreadsheetImportPlan plan;
  final int score;

  const _SmartTargetCandidate({
    required this.target,
    required this.plan,
    required this.score,
  });
}

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

  Future<void> importSmartFile({
    required Future<bool> Function(PikiSmartImportDraft draft) confirmPlan,
  }) async {
    final file = await SpreadsheetImportReader.pickRows(
      dialogTitle: 'Upload File to Piki',
      allowedExtensions: SpreadsheetImportReader.documentImportExtensions,
    );
    if (file == null) return;

    final sessionId = await _ensureSession('Smart file upload');
    await _memoryLoadFuture;
    addMessage(
      PikiMessage(
        content:
            'Upload ${file.fileName}. Let Piki read it and put it where it belongs.',
        sender: PikiSender.user,
        sessionId: sessionId,
      ),
    );

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final working = PikiMessage(
      content: 'Reading ${file.fileName} and deciding where it belongs...',
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
      final draft = await _buildSmartImportDraft(file);
      final confirmed = await confirmPlan(draft);
      if (!confirmed) {
        removeMessagesWhere((message) => message.id == working.id);
        addMessage(
          PikiMessage(
            content: 'Smart upload was cancelled. I did not change anything.',
            sender: PikiSender.agent,
            sessionId: sessionId,
          ),
        );
        return;
      }

      final result = await _importSmartDraft(draft);
      unawaited(_ref.read(syncControllerProvider.notifier).refreshLocalState());
      removeMessagesWhere((message) => message.id == working.id);

      final content = _smartImportSummary(result);
      final toolResult = _smartImportToolResult(result, draft);
      addMessage(
        PikiMessage(
          content: content,
          sender: PikiSender.agent,
          sessionId: sessionId,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': toolResult['type'],
            'model': OpenRouterService.modelName,
            'tool_results': [toolResult],
          },
          suggestions: _smartImportSuggestions(draft.target),
        ),
      );
      _ref
          .read(pikiBrainProvider)
          .rememberInteraction(
            userInput: 'Smart upload ${file.fileName}',
            reply: content,
            tools: const ['smart_import'],
            results: [toolResult],
          );
      _ref.read(pikiInsightProvider.notifier).state = PikiInsightData(
        text: _smartImportInsight(result, draft),
      );
    } catch (error) {
      removeMessagesWhere((message) => message.id == working.id);
      addMessage(
        PikiMessage(
          content: AppErrorMessage.withContext(
            error,
            prefix: 'Piki could not finish that upload.',
            fallback:
                'Try a clearer Excel, CSV, PDF, DOCX, TXT, or JSON file with product, sales, customer, or expense rows.',
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

  Future<void> importProductsFromFile({
    required Future<bool> Function(SpreadsheetImportPlan plan) confirmPlan,
  }) async {
    await _importPickedProductFile(confirmPlan: confirmPlan);
  }

  Future<void> importSalesFromFile({
    required Future<bool> Function(SpreadsheetImportPlan plan) confirmPlan,
  }) async {
    await _importPickedSalesFile(confirmPlan: confirmPlan);
  }

  Future<void> _importPickedProductFile({
    required Future<bool> Function(SpreadsheetImportPlan plan) confirmPlan,
  }) async {
    final file = await SpreadsheetImportReader.pickRows(
      dialogTitle: 'Import Products with Piki Chat',
      allowedExtensions: SpreadsheetImportReader.productImportExtensions,
    );
    if (file == null) return;

    final sessionId = await _ensureSession('Import products');
    await _memoryLoadFuture;
    addMessage(
      PikiMessage(
        content: 'Upload ${file.fileName} and import products.',
        sender: PikiSender.user,
        sessionId: sessionId,
      ),
    );

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final working = PikiMessage(
      content: 'Reading ${file.fileName} and mapping product columns...',
      sender: PikiSender.agent,
      sessionId: sessionId,
      messageType: PikiMessageType.working,
      steps: [
        PikiAgentService.buildStepForTool(
          PikiAgentService.toolCreateProduct,
        ).copyWith(status: PikiStepStatus.working),
      ],
    );
    addMessage(working);

    try {
      final plan = await ProductImportService.buildPlanForPickedFile(file);
      final confirmed = await confirmPlan(plan);
      if (!confirmed) {
        removeMessagesWhere((message) => message.id == working.id);
        addMessage(
          PikiMessage(
            content: 'Product import was cancelled. I did not change anything.',
            sender: PikiSender.agent,
            sessionId: sessionId,
          ),
        );
        return;
      }

      final result = await ProductImportService.importPlan(plan);
      unawaited(_ref.read(syncControllerProvider.notifier).refreshLocalState());
      removeMessagesWhere((message) => message.id == working.id);

      final content = _productImportSummary(result);
      addMessage(
        PikiMessage(
          content: content,
          sender: PikiSender.agent,
          sessionId: sessionId,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': 'product_import',
            'model': OpenRouterService.modelName,
            'tool_results': [_productImportToolResult(result, plan)],
          },
          suggestions: const ['Show product catalog', 'Check low stock items'],
        ),
      );
      _ref
          .read(pikiBrainProvider)
          .rememberInteraction(
            userInput: 'Import products from ${file.fileName}',
            reply: content,
            tools: const ['product_import'],
            results: [_productImportToolResult(result, plan)],
          );
      _ref.read(pikiInsightProvider.notifier).state = PikiInsightData(
        text:
            'Imported ${result.imported} product row${result.imported == 1 ? '' : 's'} from ${file.fileName}.',
      );
    } catch (error) {
      removeMessagesWhere((message) => message.id == working.id);
      addMessage(
        PikiMessage(
          content: AppErrorMessage.withContext(
            error,
            prefix: 'Could not import products.',
            fallback:
                'Use an Excel, CSV, PDF, DOCX, TXT, or JSON file with product names. Existing products can be updated with sku, barcode, or product_id.',
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

  Future<void> _importPickedSalesFile({
    required Future<bool> Function(SpreadsheetImportPlan plan) confirmPlan,
  }) async {
    final file = await SpreadsheetImportReader.pickRows(
      dialogTitle: 'Import Sales with Piki Chat',
      allowedExtensions: SaleImportService.supportedExtensions,
    );
    if (file == null) return;

    final sessionId = await _ensureSession('Import sales');
    await _memoryLoadFuture;
    addMessage(
      PikiMessage(
        content: 'Upload ${file.fileName} and import sales records.',
        sender: PikiSender.user,
        sessionId: sessionId,
      ),
    );

    final statusNotifier = _ref.read(pikiStatusProvider.notifier);
    statusNotifier.state = AgentStatus.working;
    final working = PikiMessage(
      content: 'Reading ${file.fileName} and mapping sales records...',
      sender: PikiSender.agent,
      sessionId: sessionId,
      messageType: PikiMessageType.working,
      steps: [
        PikiAgentService.buildStepForTool(
          PikiAgentService.toolRecordProductSale,
        ).copyWith(status: PikiStepStatus.working),
      ],
    );
    addMessage(working);

    try {
      final plan = await SaleImportService.buildPlanForPickedFile(file);
      final confirmed = await confirmPlan(plan);
      if (!confirmed) {
        removeMessagesWhere((message) => message.id == working.id);
        addMessage(
          PikiMessage(
            content: 'Sales import was cancelled. I did not change anything.',
            sender: PikiSender.agent,
            sessionId: sessionId,
          ),
        );
        return;
      }

      final result = await SaleImportService.importPlan(plan);
      unawaited(_ref.read(syncControllerProvider.notifier).refreshLocalState());
      removeMessagesWhere((message) => message.id == working.id);

      final content = _salesImportSummary(result);
      addMessage(
        PikiMessage(
          content: content,
          sender: PikiSender.agent,
          sessionId: sessionId,
          messageType: PikiMessageType.aiResponse,
          attachedData: {
            'type': 'sales_import',
            'model': OpenRouterService.modelName,
            'tool_results': [_salesImportToolResult(result, plan)],
          },
          suggestions: const [
            "Show today's sales summary",
            'Show sales report',
          ],
        ),
      );
      _ref
          .read(pikiBrainProvider)
          .rememberInteraction(
            userInput: 'Import sales from ${file.fileName}',
            reply: content,
            tools: const ['sales_import'],
            results: [_salesImportToolResult(result, plan)],
          );
      _ref.read(pikiInsightProvider.notifier).state = PikiInsightData(
        text:
            'Imported ${result.imported} sale row${result.imported == 1 ? '' : 's'} from ${file.fileName}.',
      );
    } catch (error) {
      removeMessagesWhere((message) => message.id == working.id);
      addMessage(
        PikiMessage(
          content: AppErrorMessage.withContext(
            error,
            prefix: 'Could not import sales.',
            fallback:
                'Use an Excel, CSV, PDF, DOCX, TXT, or JSON file with total for summary sales, or product/service identifier columns for itemized sales.',
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

  Future<PikiSmartImportDraft> _buildSmartImportDraft(
    SpreadsheetFileRows file,
  ) async {
    if (SpreadsheetImportReader.isSpreadsheetExtension(file.extension)) {
      final candidates = _rankSpreadsheetTargets(file);
      final errors = <String>[];
      for (final candidate in candidates) {
        try {
          final plan = await _buildPlanWithCloudForTarget(
            candidate.target,
            file.rows,
            fileName: file.fileName,
          );
          return PikiSmartImportDraft(
            target: candidate.target,
            plan: plan.copyWith(
              warnings: _dedupeStrings([
                ...plan.warnings,
                'Piki smart upload classified this spreadsheet as ${_targetLabel(candidate.target)}.',
              ]),
            ),
            fileName: file.fileName,
          );
        } catch (error) {
          errors.add(_shortError(error));
        }
      }
      throw Exception(
        errors.isEmpty
            ? 'Piki could not decide where this spreadsheet belongs.'
            : 'Piki could not safely map this spreadsheet. ${errors.first}',
      );
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read the selected file.');
    }
    final cloud = await OpenRouterService.extractSmartImportRows(
      fileName: file.fileName,
      bytes: bytes,
      mimeType: file.mimeType,
      extension: file.extension,
    );
    final target = _targetFromCloud(cloud['target']);
    final rows = _rowsFromCloudSmartFile(cloud);
    final plan = _buildPlanForTarget(target, rows, fileName: file.fileName);
    return PikiSmartImportDraft(
      target: target,
      plan: plan.copyWith(
        warnings: _dedupeStrings([
          ...plan.warnings,
          'Piki smart upload classified this file as ${_targetLabel(target)}.',
          ..._cloudWarnings(cloud),
        ]),
      ),
      fileName: file.fileName,
    );
  }

  List<_SmartTargetCandidate> _rankSpreadsheetTargets(
    SpreadsheetFileRows file,
  ) {
    final candidates = <_SmartTargetCandidate>[];
    for (final target in PikiSmartImportTarget.values) {
      try {
        final plan = _buildPlanForTarget(
          target,
          file.rows,
          fileName: file.fileName,
        );
        candidates.add(
          _SmartTargetCandidate(
            target: target,
            plan: plan,
            score: _scoreSmartTarget(target, plan, file.fileName),
          ),
        );
      } catch (_) {
        // A failed local plan means this target is not a likely fit.
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  int _scoreSmartTarget(
    PikiSmartImportTarget target,
    SpreadsheetImportPlan plan,
    String fileName,
  ) {
    final fields = plan.headers.toSet();
    final raw = [
      fileName,
      ...plan.rawHeaders,
      ...plan.sampleRows
          .take(2)
          .expand((row) => row.entries.take(4).map((entry) => entry.value)),
    ].join(' ').toLowerCase();

    var score = plan.mappedColumns.length * 10 + plan.dataRowCount;
    bool hasAny(Iterable<String> values) => values.any(fields.contains);
    bool textHas(Iterable<String> words) => words.any(raw.contains);

    switch (target) {
      case PikiSmartImportTarget.products:
        if (hasAny(['sku', 'barcode', 'price', 'cost', 'stock', 'category'])) {
          score += 65;
        }
        if (textHas(['product', 'catalog', 'inventory', 'stock', 'sku'])) {
          score += 50;
        }
        break;
      case PikiSmartImportTarget.sales:
        if (hasAny(['total', 'payment_type', 'date', 'reference'])) {
          score += 80;
        }
        if (hasAny(['product', 'service', 'quantity', 'unit_price'])) {
          score += 35;
        }
        if (textHas(['sales', 'receipt', 'transaction', 'invoice'])) {
          score += 55;
        }
        break;
      case PikiSmartImportTarget.customers:
        if (hasAny(['phone', 'email', 'customer_id'])) {
          score += 90;
        } else {
          score -= 35;
        }
        if (textHas(['customer', 'contact', 'client', 'phone', 'email'])) {
          score += 70;
        }
        break;
      case PikiSmartImportTarget.expenses:
        if (hasAny(['amount', 'category', 'date', 'note'])) {
          score += 70;
        }
        if (fields.contains('title') && fields.contains('amount')) {
          score += 45;
        }
        if (textHas(['expense', 'expenses', 'spending', 'paid', 'bill'])) {
          score += 75;
        }
        break;
    }
    return score;
  }

  Future<SpreadsheetImportPlan> _buildPlanWithCloudForTarget(
    PikiSmartImportTarget target,
    List<List<String>> rows, {
    required String fileName,
  }) {
    switch (target) {
      case PikiSmartImportTarget.products:
        return ProductImportService.buildPlanWithCloud(
          rows,
          fileName: fileName,
        );
      case PikiSmartImportTarget.sales:
        return SaleImportService.buildPlanWithCloud(rows, fileName: fileName);
      case PikiSmartImportTarget.customers:
        return CustomerImportService.buildPlanWithCloud(
          rows,
          fileName: fileName,
        );
      case PikiSmartImportTarget.expenses:
        return ExpenseImportService.buildPlanWithCloud(
          rows,
          fileName: fileName,
        );
    }
  }

  SpreadsheetImportPlan _buildPlanForTarget(
    PikiSmartImportTarget target,
    List<List<String>> rows, {
    required String fileName,
  }) {
    switch (target) {
      case PikiSmartImportTarget.products:
        return ProductImportService.buildPlan(rows, fileName: fileName);
      case PikiSmartImportTarget.sales:
        return SaleImportService.buildPlan(rows, fileName: fileName);
      case PikiSmartImportTarget.customers:
        return CustomerImportService.buildPlan(rows, fileName: fileName);
      case PikiSmartImportTarget.expenses:
        return ExpenseImportService.buildPlan(rows, fileName: fileName);
    }
  }

  Future<_SmartImportResult> _importSmartDraft(
    PikiSmartImportDraft draft,
  ) async {
    switch (draft.target) {
      case PikiSmartImportTarget.products:
        return _SmartImportResult(
          target: draft.target,
          result: await ProductImportService.importPlan(draft.plan),
        );
      case PikiSmartImportTarget.sales:
        return _SmartImportResult(
          target: draft.target,
          result: await SaleImportService.importPlan(draft.plan),
        );
      case PikiSmartImportTarget.customers:
        return _SmartImportResult(
          target: draft.target,
          result: await CustomerImportService.importPlan(draft.plan),
        );
      case PikiSmartImportTarget.expenses:
        return _SmartImportResult(
          target: draft.target,
          result: await ExpenseImportService.importPlan(draft.plan),
        );
    }
  }

  PikiSmartImportTarget _targetFromCloud(Object? value) {
    final clean = value.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return switch (clean) {
      'products' ||
      'product' ||
      'catalog' ||
      'inventory' => PikiSmartImportTarget.products,
      'sales' ||
      'sale' ||
      'transactions' ||
      'receipts' => PikiSmartImportTarget.sales,
      'customers' ||
      'customer' ||
      'contacts' ||
      'clients' => PikiSmartImportTarget.customers,
      'expenses' ||
      'expense' ||
      'spending' ||
      'costs' => PikiSmartImportTarget.expenses,
      _ => throw Exception('Piki could not decide where this file belongs.'),
    };
  }

  List<List<String>> _rowsFromCloudSmartFile(Map<String, dynamic> cloud) {
    final headers =
        (cloud['headers'] as List?)?.map((item) => item.toString()).toList() ??
        const <String>[];
    final rows =
        (cloud['rows'] as List?)
            ?.whereType<List>()
            .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
            .toList() ??
        const <List<String>>[];
    if (headers.isEmpty || rows.isEmpty) {
      throw Exception('Piki could not find import rows in this file.');
    }
    return [headers, ...rows];
  }

  List<String> _cloudWarnings(Map<String, dynamic> cloud) {
    final warnings = <String>[];
    final summary = cloud['summary']?.toString().trim();
    if (summary != null && summary.isNotEmpty) {
      warnings.add(summary);
    }
    final rawWarnings = cloud['warnings'];
    if (rawWarnings is List) {
      warnings.addAll(
        rawWarnings
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      );
    }
    if (cloud['sourceTextTruncated'] == true) {
      warnings.add(
        'The file was long, so Piki reviewed the first part of the extracted text.',
      );
    }
    return _dedupeStrings(warnings);
  }

  List<String> _dedupeStrings(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) continue;
      final key = clean.toLowerCase();
      if (seen.add(key)) {
        result.add(clean);
      }
    }
    return result;
  }

  String _shortError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _targetLabel(PikiSmartImportTarget target) {
    return switch (target) {
      PikiSmartImportTarget.products => 'products',
      PikiSmartImportTarget.sales => 'sales records',
      PikiSmartImportTarget.customers => 'customers',
      PikiSmartImportTarget.expenses => 'expenses',
    };
  }

  List<String> _smartImportSuggestions(PikiSmartImportTarget target) {
    return switch (target) {
      PikiSmartImportTarget.products => const [
        'Show product catalog',
        'Check low stock items',
      ],
      PikiSmartImportTarget.sales => const [
        "Show today's sales summary",
        'Show sales report',
      ],
      PikiSmartImportTarget.customers => const [
        'Show top customers who owe money',
        'Search customers',
      ],
      PikiSmartImportTarget.expenses => const [
        'Show expense summary',
        'Show profit summary',
      ],
    };
  }

  String _smartImportInsight(
    _SmartImportResult result,
    PikiSmartImportDraft draft,
  ) {
    return switch (result.target) {
      PikiSmartImportTarget.products =>
        'Imported ${(result.result as ProductImportResult).imported} product row${(result.result as ProductImportResult).imported == 1 ? '' : 's'} from ${draft.fileName}.',
      PikiSmartImportTarget.sales =>
        'Imported ${(result.result as SaleImportResult).imported} sale row${(result.result as SaleImportResult).imported == 1 ? '' : 's'} from ${draft.fileName}.',
      PikiSmartImportTarget.customers =>
        'Imported ${(result.result as CustomerImportResult).imported} customer row${(result.result as CustomerImportResult).imported == 1 ? '' : 's'} from ${draft.fileName}.',
      PikiSmartImportTarget.expenses =>
        'Imported ${(result.result as ExpenseImportResult).imported} expense row${(result.result as ExpenseImportResult).imported == 1 ? '' : 's'} from ${draft.fileName}.',
    };
  }

  String _smartImportSummary(_SmartImportResult smart) {
    return switch (smart.target) {
      PikiSmartImportTarget.products => _productImportSummary(
        smart.result as ProductImportResult,
      ),
      PikiSmartImportTarget.sales => _salesImportSummary(
        smart.result as SaleImportResult,
      ),
      PikiSmartImportTarget.customers => _customerImportSummary(
        smart.result as CustomerImportResult,
      ),
      PikiSmartImportTarget.expenses => _expenseImportSummary(
        smart.result as ExpenseImportResult,
      ),
    };
  }

  Map<String, dynamic> _smartImportToolResult(
    _SmartImportResult smart,
    PikiSmartImportDraft draft,
  ) {
    return switch (smart.target) {
      PikiSmartImportTarget.products => _productImportToolResult(
        smart.result as ProductImportResult,
        draft.plan,
      ),
      PikiSmartImportTarget.sales => _salesImportToolResult(
        smart.result as SaleImportResult,
        draft.plan,
      ),
      PikiSmartImportTarget.customers => _customerImportToolResult(
        smart.result as CustomerImportResult,
        draft.plan,
      ),
      PikiSmartImportTarget.expenses => _expenseImportToolResult(
        smart.result as ExpenseImportResult,
        draft.plan,
      ),
    };
  }

  String _productImportSummary(ProductImportResult result) {
    final pieces = <String>[
      '${result.created} created',
      '${result.updated} updated',
      if (result.stockBatches > 0)
        '${result.stockBatches} stock batch${result.stockBatches == 1 ? '' : 'es'} added',
      if (result.skipped > 0) '${result.skipped} skipped',
    ];
    final errors = result.errors.isEmpty
        ? ''
        : '\n\nRows needing attention:\n${result.errors.take(4).map((error) => '- $error').join('\n')}';
    return 'Product import complete: ${pieces.join(', ')}.${errors.isEmpty ? '' : errors}';
  }

  String _salesImportSummary(SaleImportResult result) {
    final pieces = <String>[
      '${result.imported} imported',
      if (result.productLines > 0)
        '${result.productLines} product line${result.productLines == 1 ? '' : 's'}',
      if (result.serviceLines > 0)
        '${result.serviceLines} service line${result.serviceLines == 1 ? '' : 's'}',
      if (result.summaryOnly > 0)
        '${result.summaryOnly} summary sale${result.summaryOnly == 1 ? '' : 's'}',
      if (result.skipped > 0) '${result.skipped} skipped',
    ];
    final errors = result.errors.isEmpty
        ? ''
        : '\n\nRows needing attention:\n${result.errors.take(4).map((error) => '- $error').join('\n')}';
    return 'Sales import complete: ${pieces.join(', ')}.${errors.isEmpty ? '' : errors}';
  }

  String _customerImportSummary(CustomerImportResult result) {
    final pieces = <String>[
      '${result.created} created',
      '${result.updated} updated',
      if (result.skipped > 0) '${result.skipped} skipped',
    ];
    final errors = result.errors.isEmpty
        ? ''
        : '\n\nRows needing attention:\n${result.errors.take(4).map((error) => '- $error').join('\n')}';
    return 'Customer import complete: ${pieces.join(', ')}.${errors.isEmpty ? '' : errors}';
  }

  String _expenseImportSummary(ExpenseImportResult result) {
    final pieces = <String>[
      '${result.imported} imported',
      if (result.categoriesCreated > 0)
        '${result.categoriesCreated} categor${result.categoriesCreated == 1 ? 'y' : 'ies'} created',
      if (result.skipped > 0) '${result.skipped} skipped',
    ];
    final errors = result.errors.isEmpty
        ? ''
        : '\n\nRows needing attention:\n${result.errors.take(4).map((error) => '- $error').join('\n')}';
    return 'Expense import complete: ${pieces.join(', ')}.${errors.isEmpty ? '' : errors}';
  }

  Map<String, dynamic> _productImportToolResult(
    ProductImportResult result,
    SpreadsheetImportPlan plan,
  ) {
    return {
      'type': 'product_import',
      'success': true,
      'file_name': result.fileName ?? plan.fileName,
      'rows': plan.dataRowCount,
      'created': result.created,
      'updated': result.updated,
      'stock_batches': result.stockBatches,
      'skipped': result.skipped,
      'errors': result.errors,
    };
  }

  Map<String, dynamic> _salesImportToolResult(
    SaleImportResult result,
    SpreadsheetImportPlan plan,
  ) {
    return {
      'type': 'sales_import',
      'success': true,
      'file_name': result.fileName ?? plan.fileName,
      'rows': plan.dataRowCount,
      'imported': result.imported,
      'product_lines': result.productLines,
      'service_lines': result.serviceLines,
      'summary_only': result.summaryOnly,
      'skipped': result.skipped,
      'errors': result.errors,
    };
  }

  Map<String, dynamic> _customerImportToolResult(
    CustomerImportResult result,
    SpreadsheetImportPlan plan,
  ) {
    return {
      'type': 'customer_import',
      'success': true,
      'file_name': result.fileName ?? plan.fileName,
      'rows': plan.dataRowCount,
      'created': result.created,
      'updated': result.updated,
      'skipped': result.skipped,
      'errors': result.errors,
    };
  }

  Map<String, dynamic> _expenseImportToolResult(
    ExpenseImportResult result,
    SpreadsheetImportPlan plan,
  ) {
    return {
      'type': 'expense_import',
      'success': true,
      'file_name': result.fileName ?? plan.fileName,
      'rows': plan.dataRowCount,
      'imported': result.imported,
      'categories_created': result.categoriesCreated,
      'skipped': result.skipped,
      'errors': result.errors,
    };
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
