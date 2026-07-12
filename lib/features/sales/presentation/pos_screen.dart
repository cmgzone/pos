import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/cash_drawer_service.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/branch_service.dart';
import '../../../core/services/etims_service.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/services/pos_payment_service.dart';
import '../../../core/services/product_image_upload_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../agent/data/piki_models.dart';
import '../../loyalty/data/loyalty_repository.dart';
import '../../gift_cards/data/gift_card_repository.dart';
import '../../promotions/data/promotion_repository.dart';
import '../../agent/data/piki_provider.dart';
import '../../products/data/product_provider.dart';
import '../../products/data/product_repository.dart';
import '../../products/data/product_variant_color_repository.dart';
import '../../products/data/product_variant_repository.dart';
import '../../products/presentation/product_form_screen.dart';
import '../../shifts/data/shift_provider.dart';
import '../../shifts/data/shift_preferences_service.dart';
import '../../shifts/data/shift_repository.dart';
import '../../shifts/presentation/shift_auto_open_dialog.dart';
import '../../training/widgets/training_anchor.dart';

import '../data/cart_provider.dart';
import '../data/held_sale_provider.dart';
import '../data/held_sale_repository.dart';
import '../data/quotation_form_provider.dart';
import '../data/quotation_repository.dart';
import '../data/sale_repository.dart';
import '../../app/app_shell.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/presentation/customer_message_dialog.dart';
import '../../settings/data/payment_method_repository.dart';
import '../../settings/data/exchange_rate_repository.dart';
import '../../services/data/service_repository.dart';
import '../../services/data/service_provider.dart';

import 'barcode_scanner.dart';
import 'payment_checkout_dialog.dart';
import 'receipt_service.dart';
import 'widgets/variant_picker_bottom_sheet.dart';

enum PosProductViewMode { cards, compact }

final posProductViewModeProvider = StateProvider<PosProductViewMode>(
  (ref) => PosProductViewMode.cards,
);

final posRecentProductsProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => const [],
);

final posLastSelectedVariantColorProvider = StateProvider<Map<String, String>>(
  (ref) => const {},
);

final posTodayStatsProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => SaleRepository.getTodaySummary(
    cashierId: SessionService.currentUserId,
    branchId: BranchService.currentBranchId,
  ),
);

final posRecentSalesProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => SaleRepository.getAll(
    cashierId: SessionService.currentUserId,
    branchId: BranchService.currentBranchId,
    startDate: DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10),
  ),
);

/// Holds the most recently saved quotation so the Quotation cart can show
/// Print / Convert actions without leaving the POS.
final lastSavedQuotationProvider = StateProvider<Map<String, dynamic>?>(
  (ref) => null,
);

final quotationCustomerSearchProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      ref.watch(_quotationCustomerQueryProvider);
      return CustomerRepository.search(
        ref.read(_quotationCustomerQueryProvider),
      );
    });

final _quotationCustomerQueryProvider = StateProvider<String>((ref) => '');

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key, this.initialHoldId});

  final String? initialHoldId;
  static String? _pendingInitialHoldId;

  Future<void> _resumeInitialHold(
    BuildContext context,
    WidgetRef ref,
    String holdId,
  ) async {
    final heldSale = await HeldSaleRepository.takeHold(holdId);
    ref.invalidate(heldSalesProvider);
    if (!context.mounted) return;
    if (heldSale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That held sale could not be found anymore.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final items = List<Map<String, dynamic>>.from(
      heldSale['items'] as List<dynamic>? ?? const <Map<String, dynamic>>[],
    );
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That held sale has no available items to restore.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    ref.read(cartProvider.notifier).clear();
    ref.read(cartProvider.notifier).restoreHeldItems(items);
    ref.read(discountProvider.notifier).state =
        _initialHoldDouble(heldSale['discount']);
    ref.read(appliedPromotionsProvider.notifier).state = const [];
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${heldSale['name'] ?? 'Held sale'} restored to the cart.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  double _initialHoldDouble(Object? value) =>
      value is num ? value.toDouble() : (double.tryParse(value?.toString() ?? '') ?? 0.0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final isWide = MediaQuery.of(context).size.width > 900;
    final cashierName = SessionService.currentUserName;
    final cashierRole = RolePermissions.label(SessionService.currentUserRole);
    final syncState = ref.watch(syncControllerProvider);
    final currentShiftAsync = ref.watch(currentShiftProvider);
    final canOpenShifts = SessionService.canAccessFeature(
      UserAccessProfile.featureShifts,
    );

    if (initialHoldId != null) {
      _pendingInitialHoldId = initialHoldId;
    }
    if (_pendingInitialHoldId != null) {
      final holdId = _pendingInitialHoldId!;
      _pendingInitialHoldId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _resumeInitialHold(context, ref, holdId);
        }
      });
    }

    ref.listen(pikiNavigateProvider, (_, next) {
      if (next != PikiNavTarget.pos || isWide) return;
      ref.read(pikiNavigateProvider.notifier).state = PikiNavTarget.none;
      if (ref.read(cartProvider).isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _showMobileCartSheet(context, ref);
        }
      });
    });
    ref.listen<List<CartItem>>(cartProvider, (_, next) {
      unawaited(_CartSide._applyActivePromotions(ref, next));
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: isMobile
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkAccent
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.point_of_sale_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                ShopSettings.shopName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const _PikiPosVoiceAction(),
          SizedBox(width: 8),
          if (canOpenShifts && !isMobile) ...[
            _ShiftStatusChip(shiftAsync: currentShiftAsync, compact: true),
            SizedBox(width: 8),
          ],
          if (!isMobile) ...[
            _LicenseIndicatorChip(state: syncState, compact: true),
            SizedBox(width: 8),
            _SyncIndicatorChip(state: syncState, compact: true),
            SizedBox(width: AppSpacing.sm),
            _CashierAvatarButton(
              cashierName: cashierName,
              cashierRole: cashierRole,
            ),
          ],
          SizedBox(width: AppSpacing.lg),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final quotationsEnabled = ShopSettings.quotationsEnabled;
          final posMode = ref.watch(posModeProvider);
          // Responsive: side-by-side on wide screens, full-width + bottom bar on narrow
          final content = constraints.maxWidth > 900
              ? Row(
                  children: [
                    Expanded(flex: 7, child: _ProductSide()),
                    Container(
                      width: 1,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    SizedBox(
                      width: 360,
                      child: TrainingAnchor(
                        id: 'pos.cart',
                        child: posMode == PosMode.quotation
                            ? _QuotationCartSide()
                            : _CartSide(),
                      ),
                    ),
                  ],
                )
              : _ProductSide(); // Narrow/medium: full screen products + bottom action bar

          if (!quotationsEnabled) {
            return content;
          }
          return Column(
            children: [
              _PosModeTabBar(),
              Expanded(child: content),
            ],
          );
        },
      ),
      bottomNavigationBar: !isWide
          ? TrainingAnchor(
              id: 'pos.cart',
              child: _PosBottomActionBar(
                onOpenCart: () => _showMobileCartSheet(context, ref),
              ),
            )
          : null,
    );
  }

  void _showMobileCartSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.92,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkSurface
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
              Expanded(
                child: ref.watch(posModeProvider) == PosMode.quotation
                    ? _QuotationCartSide()
                    : _CartSide(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosBottomActionBar extends ConsumerWidget {
  final VoidCallback onOpenCart;

  const _PosBottomActionBar({required this.onOpenCart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(posModeProvider);
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final count = cart.length;
    final hasItems = count > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalLabel = mode == PosMode.quotation ? 'Quote total' : 'Total';
    final buttonLabel = mode == PosMode.quotation
        ? 'Review & Save Quote'
        : 'Review & Checkout';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          10,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurface
              : Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? AppColors.darkBorder
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasItems ? totalLabel : 'Cart',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    hasItems
                        ? '${ShopSettings.currency}${total.toStringAsFixed(2)}'
                        : '$count item${count == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasItems
                          ? (isDark
                                ? AppColors.darkTextPrimary
                                : Theme.of(context).colorScheme.onSurface)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.md),
            if (hasItems)
              FilledButton.icon(
                onPressed: onOpenCart,
                icon: Icon(
                  mode == PosMode.quotation
                      ? Icons.request_quote_outlined
                      : Icons.shopping_cart_checkout_rounded,
                  size: 20,
                ),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  textStyle: TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: onOpenCart,
                icon: Icon(Icons.shopping_cart_outlined, size: 20),
                label: Text('Open Cart'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CashierAvatarButton extends StatelessWidget {
  final String cashierName;
  final String cashierRole;

  const _CashierAvatarButton({
    required this.cashierName,
    required this.cashierRole,
  });

  @override
  Widget build(BuildContext context) {
    final initial = cashierName.trim().isEmpty
        ? '?'
        : cashierName.trim().substring(0, 1).toUpperCase();
    return Tooltip(
      message: cashierName.trim().isEmpty
          ? cashierRole
          : '$cashierName - $cashierRole',
      child: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.primaryLight,
        child: Text(
          initial,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PikiPosVoiceAction extends ConsumerStatefulWidget {
  const _PikiPosVoiceAction();

  @override
  ConsumerState<_PikiPosVoiceAction> createState() =>
      _PikiPosVoiceActionState();
}

class _PikiPosVoiceActionState extends ConsumerState<_PikiPosVoiceAction> {
  bool _autoListening = false;
  bool _recording = false;
  bool _busy = false;
  bool _loopRunning = false;
  int _listenToken = 0;

  static const _listenWindow = Duration(seconds: 5);
  static const _restartDelay = Duration(milliseconds: 650);

  @override
  void dispose() {
    _listenToken++;
    unawaited(SpeechService.stopListening());
    unawaited(SpeechService.stopPlayback());
    super.dispose();
  }

  Future<void> _toggleAutoListen() async {
    if (_autoListening) {
      await _stopAutoListen();
      return;
    }
    final token = ++_listenToken;
    setState(() => _autoListening = true);
    unawaited(_startLoopWhenReady(token));
  }

  Future<void> _startLoopWhenReady(int token) async {
    while (_loopRunning && mounted && token == _listenToken) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || !_autoListening || token != _listenToken) return;
    await _runAutoListenLoop(token);
  }

  Future<void> _stopAutoListen({bool stopPlayback = true}) async {
    _listenToken++;
    if (mounted) {
      setState(() {
        _autoListening = false;
        _recording = false;
        _busy = false;
      });
    }
    await SpeechService.stopListening();
    if (stopPlayback) {
      await SpeechService.stopPlayback();
    }
  }

  Future<void> _runAutoListenLoop(int token) async {
    if (_loopRunning) return;
    _loopRunning = true;
    try {
      while (mounted && _autoListening && token == _listenToken) {
        setState(() {
          _recording = true;
          _busy = false;
        });

        final started = await SpeechService.startRecording();
        if (!started) {
          if (mounted) {
            setState(() {
              _autoListening = false;
              _recording = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Microphone permission or recorder is unavailable.',
                ),
              ),
            );
          }
          return;
        }

        await Future<void>.delayed(_listenWindow);
        if (!mounted || !_autoListening || token != _listenToken) {
          await SpeechService.stopListening();
          break;
        }

        setState(() {
          _recording = false;
          _busy = true;
        });

        try {
          final text = await SpeechService.stopAndTranscribe();
          if (!mounted || !_autoListening || token != _listenToken) {
            break;
          }
          if (_isStopCommand(text)) {
            await SpeechService.speak('Auto listen is off.');
            await _stopAutoListen(stopPlayback: false);
            break;
          }
          if (_shouldSend(text)) {
            await _sendPikiCommand(text);
          }
        } catch (error) {
          if (mounted && _autoListening && token == _listenToken) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppErrorMessage.withContext(
                    error,
                    prefix: 'Piki auto listen failed.',
                    fallback: AppErrorMessage.pikiFailed,
                  ),
                ),
              ),
            );
          }
        } finally {
          if (mounted && token == _listenToken) {
            setState(() => _busy = false);
          }
        }

        await Future<void>.delayed(_restartDelay);
      }
    } finally {
      _loopRunning = false;
      if (mounted && token == _listenToken) {
        setState(() {
          _autoListening = false;
          _recording = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _sendPikiCommand(String text) async {
    final previousMode = ref.read(pikiModeProvider);
    final mode = await _resolvePosVoiceMode(text);
    ref.read(pikiModeProvider.notifier).state = mode;
    final beforeIds = ref
        .read(pikiMessagesProvider)
        .map((message) => message.id)
        .toSet();
    try {
      await ref.read(pikiMessagesProvider.notifier).sendMessage(text.trim());
      await _speakLatestAgentReply(beforeIds);
    } finally {
      ref.read(pikiModeProvider.notifier).state = previousMode;
    }
  }

  Future<PikiMode> _resolvePosVoiceMode(String text) async {
    final normalized = _normalizeVoiceText(text);
    if (normalized.isEmpty) return PikiMode.plan;
    if (_isAdviceRequest(normalized)) return PikiMode.advice;
    if (_isExplicitCartCommand(normalized)) return PikiMode.sell;
    if (_isGeneralPosQuestion(normalized)) return PikiMode.plan;
    if (_isPlainProductPhrase(normalized)) {
      final matches = await ProductRepository.searchForPos(normalized);
      if (matches.isNotEmpty) return PikiMode.sell;
    }
    return PikiMode.plan;
  }

  Future<void> _speakLatestAgentReply(Set<String> beforeIds) async {
    final replies = ref
        .read(pikiMessagesProvider)
        .where(
          (message) =>
              !beforeIds.contains(message.id) &&
              message.sender == PikiSender.agent &&
              message.messageType != PikiMessageType.thinking &&
              message.messageType != PikiMessageType.working &&
              message.content.trim().isNotEmpty,
        )
        .toList();
    if (replies.isEmpty) return;
    await SpeechService.speak(replies.last.content);
  }

  bool _shouldSend(String text) => text.trim().length >= 2;

  String _normalizeVoiceText(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[,;.!?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^(please|piki|hey piki|okay piki)\s+'), '')
        .trim();
  }

  bool _isAdviceRequest(String text) {
    return _containsAny(text, const [
      'advice',
      'advise',
      'recommend',
      'suggest',
      'strategy',
      'coach',
      'improve',
      'what should',
      'should i',
      'how can i',
      'how do i improve',
    ]);
  }

  bool _isExplicitCartCommand(String text) {
    if (_containsAny(text, const [
      'checkout',
      'check out',
      'process sale',
      'pay now',
      'complete sale',
      'finish sale',
      'done selling',
      'charge customer',
      'clear cart',
      'empty cart',
      'remove all',
      'clear all',
      'reset cart',
      'cancel cart',
      'hold sale',
      'hold this sale',
      'park sale',
      'save sale',
      'suspend sale',
      'same again',
      'add another',
      'another one',
      'one more',
      'add one more',
    ])) {
      return true;
    }

    return RegExp(
          r'^(?:sell|add|ring up|give me|scan|get|put|cart)\s+.+$',
        ).hasMatch(text) ||
        RegExp(
          r'^(?:remove|delete|void|take off|take out)\s+.+$',
        ).hasMatch(text) ||
        RegExp(r'^(?:set|change|make)\s+.+\s+\d+(?:\.\d+)?$').hasMatch(text) ||
        RegExp(r'^(.+?)\s+x\s*\d+(?:\.\d+)?$').hasMatch(text) ||
        RegExp(
          r'^(?:a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozen|\d+(?:\.\d+)?)\s+.+$',
        ).hasMatch(text);
  }

  bool _isGeneralPosQuestion(String text) {
    return text.endsWith('?') ||
        _containsAny(text, const [
          'what ',
          'why ',
          'how ',
          'when ',
          'where ',
          'who ',
          'show ',
          'tell ',
          'check ',
          'list ',
          'report',
          'summary',
          'sales',
          'stock',
          'inventory',
          'profit',
          'expense',
          'debtor',
          'customer',
          'supplier',
          'purchase',
          'restock',
          'low stock',
          'expiry',
          'expired',
          'shift',
          'cash',
          'debt',
          'due',
          'payment',
          'today',
          'yesterday',
          'week',
          'month',
          'alert',
        ]);
  }

  bool _isPlainProductPhrase(String text) {
    if (text.isEmpty || text.length > 60) return false;
    final words = text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    if (words.isEmpty || words.length > 4) return false;
    return !RegExp(r'[^a-z0-9\s._-]').hasMatch(text);
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  bool _isStopCommand(String text) {
    final normalized = _normalizeVoiceText(
      text,
    ).replaceAll(RegExp(r'[^\w\s]'), '');
    return normalized == 'stop listening' ||
        normalized == 'piki stop listening' ||
        normalized == 'pause listening' ||
        normalized == 'piki pause listening' ||
        normalized == 'auto listen off' ||
        normalized == 'turn off auto listen' ||
        normalized == 'stop auto listen';
  }

  @override
  Widget build(BuildContext context) {
    final active = _autoListening || _recording || _busy;
    return Tooltip(
      message: _autoListening
          ? 'Stop Piki auto listen'
          : 'Start Piki auto listen',
      child: IconButton(
        onPressed: _toggleAutoListen,
        icon: Icon(
          active ? Icons.hearing_rounded : Icons.hearing_outlined,
          color: active ? AppColors.primaryLight : null,
        ),
      ),
    );
  }
}

class _SyncIndicatorChip extends StatelessWidget {
  final SyncState state;
  final bool compact;

  const _SyncIndicatorChip({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final config = _resolveIndicatorStyle(context, state);

    if (compact) {
      return Tooltip(
        message: config.label,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(config.icon, size: 20, color: config.color),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(config.icon, size: 16, color: config.color),
          SizedBox(width: 6),
          Text(
            config.label,
            style: TextStyle(color: config.color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  _SyncIndicatorStyle _resolveIndicatorStyle(
    BuildContext context,
    SyncState state,
  ) {
    switch (state.indicator) {
      case SyncIndicatorState.localOnly:
        return _SyncIndicatorStyle(
          icon: Icons.cloud_off,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          label: 'Local Only',
        );
      case SyncIndicatorState.offline:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_off_outlined,
          color: AppColors.warning,
          label: 'Offline',
        );
      case SyncIndicatorState.syncing:
        return const _SyncIndicatorStyle(
          icon: Icons.sync,
          color: AppColors.primaryLight,
          label: 'Syncing',
        );
      case SyncIndicatorState.error:
        return const _SyncIndicatorStyle(
          icon: Icons.sync_problem,
          color: AppColors.error,
          label: 'Sync Error',
        );
      case SyncIndicatorState.issues:
        return const _SyncIndicatorStyle(
          icon: Icons.warning_amber_rounded,
          color: AppColors.warning,
          label: 'Needs Review',
        );
      case SyncIndicatorState.pending:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_upload_outlined,
          color: AppColors.warning,
          label: 'Pending Sync',
        );
      case SyncIndicatorState.updatesAvailable:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_download_outlined,
          color: AppColors.primaryLight,
          label: 'Updates Ready',
        );
      case SyncIndicatorState.synced:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_done,
          color: AppColors.success,
          label: 'Synced',
        );
    }
  }
}

class _ShiftStatusChip extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>?> shiftAsync;
  final bool compact;

  const _ShiftStatusChip({required this.shiftAsync, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final shift = shiftAsync.valueOrNull;
    final isOpen = shift != null;
    final label = shiftAsync.isLoading
        ? 'Checking shift'
        : isOpen
        ? 'Shift Open'
        : 'Open Shift';
    final color = isOpen ? AppColors.success : AppColors.warning;

    if (compact) {
      return Tooltip(
        message: label,
        child: IconButton(
          onPressed: () => AppShell.selectIndex(10),
          icon: shiftAsync.isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isOpen ? Icons.timer_rounded : Icons.lock_clock_outlined,
                  size: 20,
                  color: color,
                ),
        ),
      );
    }

    return TextButton.icon(
      onPressed: () => AppShell.selectIndex(10),
      icon: shiftAsync.isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isOpen ? Icons.timer_rounded : Icons.lock_clock_outlined,
              size: 18,
              color: color,
            ),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

class _LicenseIndicatorChip extends StatelessWidget {
  final SyncState state;
  final bool compact;

  const _LicenseIndicatorChip({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final license = state.licenseSnapshot;
    final color = switch (license.accessStatus) {
      LicenseAccessStatus.active => AppColors.success,
      LicenseAccessStatus.grace => AppColors.warning,
      LicenseAccessStatus.expired ||
      LicenseAccessStatus.invalid => AppColors.error,
      LicenseAccessStatus.localOnly => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };
    final icon = switch (license.accessStatus) {
      LicenseAccessStatus.active => Icons.verified_outlined,
      LicenseAccessStatus.grace => Icons.schedule_outlined,
      LicenseAccessStatus.expired => Icons.lock_clock_outlined,
      LicenseAccessStatus.invalid => Icons.gpp_bad_outlined,
      LicenseAccessStatus.localOnly => Icons.offline_bolt_outlined,
    };
    final label = switch (license.accessStatus) {
      LicenseAccessStatus.active => 'Active',
      LicenseAccessStatus.grace => 'Grace',
      LicenseAccessStatus.expired => 'Expired',
      LicenseAccessStatus.invalid => 'License Error',
      LicenseAccessStatus.localOnly => 'Local Only',
    };

    if (compact) {
      return Tooltip(
        message: 'License: $label',
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: Icon(icon, size: 20, color: color)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: AppSpacing.xs),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SyncIndicatorStyle {
  final IconData icon;
  final Color color;
  final String label;

  const _SyncIndicatorStyle({
    required this.icon,
    required this.color,
    required this.label,
  });
}

// ──────────────── POS MODE TABS ────────────────

class _PosModeTabBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(posModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark
          ? AppColors.darkSurface
          : Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          _ModeTab(
            label: 'Sale',
            icon: Icons.point_of_sale_rounded,
            selected: mode == PosMode.sale,
            onTap: () => _switchMode(context, ref, PosMode.sale),
          ),
          SizedBox(width: AppSpacing.sm),
          _ModeTab(
            label: 'Quotation',
            icon: Icons.request_quote_outlined,
            selected: mode == PosMode.quotation,
            onTap: () => _switchMode(context, ref, PosMode.quotation),
          ),
        ],
      ),
    );
  }

  Future<void> _switchMode(
    BuildContext context,
    WidgetRef ref,
    PosMode target,
  ) async {
    final current = ref.read(posModeProvider);
    if (current == target) return;

    final cart = ref.read(cartProvider);
    if (cart.isNotEmpty) {
      final label = target.name[0].toUpperCase() + target.name.substring(1);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Switch to $label?'),
          content: Text(
            'Switching will clear the ${cart.length} item${cart.length == 1 ? '' : 's'} '
            'already in the cart.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Switch'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      _clearCartAndForm(ref);
    }

    ref.read(posModeProvider.notifier).state = target;
  }

  void _clearCartAndForm(WidgetRef ref) {
    ref.read(cartProvider.notifier).clear();
    ref.read(discountProvider.notifier).state = 0.0;
    ref.read(quotationCustomerProvider.notifier).state = null;
    ref.read(quotationExpiryProvider.notifier).state = null;
    ref.read(quotationNotesProvider.notifier).state = '';
    ref.read(lastSavedQuotationProvider.notifier).state = null;
    ref.read(activeQuotationIdProvider.notifier).state = null;
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.primary;
    final bg = selected ? accent : Colors.transparent;
    final fg = selected
        ? Colors.white
        : (isDark
              ? AppColors.darkTextSecondary
              : Theme.of(context).colorScheme.onSurfaceVariant);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : (isDark ? AppColors.darkBorder : AppColors.border),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(icon, size: 15, color: fg),
                SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────── LEFT SIDE: Products ────────────────

class _ProductSide extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProductSide> createState() => _ProductSideState();
}

class _ProductSideState extends ConsumerState<_ProductSide> {
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  bool _isVariantProduct(Map<String, dynamic> product) =>
      ((product['has_variants'] as num?) ?? 0) == 1;

  Map<String, dynamic>? _matchedVariantFromSearchResult(
    Map<String, dynamic> product,
  ) {
    if (product['result_type'] != 'variant' &&
        product['result_type'] != 'serial') {
      return null;
    }

    final variantId = product['matched_variant_id'] as String?;
    if (variantId == null || variantId.trim().isEmpty) {
      return null;
    }

    return {
      'id': variantId,
      'product_id': product['id'],
      'name': product['matched_variant_name'],
      'sku': product['matched_variant_sku'],
      'barcode': product['matched_variant_barcode'],
      'price': product['matched_variant_price'],
      'cost': product['matched_variant_cost'],
      'stock': product['matched_variant_stock'],
      'low_stock': product['matched_variant_low_stock'],
    };
  }

  String? _matchedSerialFromSearchResult(Map<String, dynamic> product) {
    if (product['result_type'] != 'serial') {
      return null;
    }
    final serial = product['matched_serial_number']?.toString().trim() ?? '';
    return serial.isEmpty ? null : serial;
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChange);
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusSearchField() {
    if (!mounted || !Platform.isWindows) {
      return;
    }
    _searchFocusNode.requestFocus();
  }

  void _clearSearch({bool refocus = true}) {
    _searchController.clear();
    ref.read(productSearchProvider.notifier).state = '';
    if (refocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
    }
  }

  String? _categoryNameFor(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> categories,
  ) {
    final catId = product['category_id'] as String?;
    if (catId == null) return null;
    return categories.firstWhere(
          (category) => category['id'] == catId,
          orElse: () => const <String, dynamic>{},
        )['name']
        as String?;
  }

  Future<void> _openProductForm({String? initialSearch}) async {
    final initialName = initialSearch?.trim();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          initialName: initialName?.isEmpty == true ? null : initialName,
        ),
      ),
    );
    if (result == true) {
      ref.invalidate(filteredProductsProvider);
      ref.invalidate(productsProvider(null));
      _clearSearch(refocus: Platform.isWindows);
    } else if ((initialSearch ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
    }
  }

  void _rememberQuickPick(Map<String, dynamic> product) {
    final id = product['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      return;
    }
    final item = Map<String, dynamic>.from(product);
    final current = ref.read(posRecentProductsProvider);
    ref.read(posRecentProductsProvider.notifier).state = [
      item,
      ...current.where((existing) => existing['id'] != id),
    ].take(8).toList(growable: false);
  }

  List<Map<String, dynamic>> _mergeQuickPicks(
    List<Map<String, dynamic>> recent,
    List<Map<String, dynamic>> products,
  ) {
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final product in [...recent, ...products]) {
      final id = product['id'] as String?;
      if (id == null || id.isEmpty || seen.contains(id)) {
        continue;
      }
      seen.add(id);
      merged.add(product);
      if (merged.length == 8) {
        break;
      }
    }
    return merged;
  }

  String _cartLabel(
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
    Map<String, dynamic>? variantColor,
    List<String> serialNumbers = const [],
  }) {
    final productName = product['name'] as String? ?? 'Product';
    final variantName = variant?['name'] as String? ?? '';
    final colorName = variantColor?['name'] as String? ?? '';
    final parts = <String>[productName];
    if (variantName.trim().isNotEmpty) {
      parts.add(variantName.trim());
    }
    if (colorName.trim().isNotEmpty) {
      parts.add(colorName.trim());
    }
    if (serialNumbers.isNotEmpty) {
      parts.add(serialNumbers.join(', '));
    }
    return parts.join(' - ');
  }

  void _showAddToCartSnackBar(
    bool success,
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
    Map<String, dynamic>? variantColor,
    List<String> serialNumbers = const [],
  }) {
    if (!mounted) {
      return;
    }

    final label = _cartLabel(
      product,
      variant: variant,
      variantColor: variantColor,
      serialNumbers: serialNumbers,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.warning_amber,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                success
                    ? '$label added to cart'
                    : 'Not enough stock for $label!',
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? AppColors.success : AppColors.error,
        width: 360,
      ),
    );
  }

  bool _addProductToCart(
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
    Map<String, dynamic>? variantColor,
    List<String> serialNumbers = const [],
  }) {
    final success = ref
        .read(cartProvider.notifier)
        .addProduct(
          product,
          variant: variant,
          variantColor: variantColor,
          serialNumbers: serialNumbers,
        );
    if (success) {
      _rememberQuickPick(product);
      _rememberVariantColor(product, variant, variantColor);
    }
    _showAddToCartSnackBar(
      success,
      product,
      variant: variant,
      variantColor: variantColor,
      serialNumbers: serialNumbers,
    );
    _clearSearch();
    return success;
  }

  String _variantColorSelectionKey(
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
  ) {
    return '${product['id']}_${variant['id']}';
  }

  void _rememberVariantColor(
    Map<String, dynamic> product,
    Map<String, dynamic>? variant,
    Map<String, dynamic>? variantColor,
  ) {
    final colorId = variantColor?['id']?.toString();
    if (variant == null || colorId == null || colorId.trim().isEmpty) {
      return;
    }
    final key = _variantColorSelectionKey(product, variant);
    ref.read(posLastSelectedVariantColorProvider.notifier).state = {
      ...ref.read(posLastSelectedVariantColorProvider),
      key: colorId,
    };
  }

  String? _lastSelectedColorId(
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
  ) {
    return ref.read(
      posLastSelectedVariantColorProvider,
    )[_variantColorSelectionKey(product, variant)];
  }

  Map<String, List<Map<String, dynamic>>> _colorsByVariantId(
    List<Map<String, dynamic>> colors,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final color in colors) {
      final variantId = color['variant_id']?.toString();
      if (variantId == null || variantId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(variantId, () => []).add(color);
    }
    return grouped;
  }

  bool _variantColorOutOfStock(
    Map<String, dynamic> product,
    Map<String, dynamic> color,
  ) {
    return UnitUtils.tracksStock(product) &&
        ((color['stock'] as num?) ?? 0).toDouble() <= 0;
  }

  void _showVariantColorUnavailableSnackBar(
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
    Map<String, dynamic> color,
  ) {
    if (!mounted) {
      return;
    }
    final label = _cartLabel(product, variant: variant, variantColor: color);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label is out of stock.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
        width: 360,
      ),
    );
  }

  void _closeVariantPicker(BuildContext? bottomSheetContext) {
    if (bottomSheetContext != null && bottomSheetContext.mounted) {
      Navigator.pop(bottomSheetContext);
    }
  }

  Future<void> _handleVariantSelection(
    Map<String, dynamic> product,
    Map<String, dynamic> variant, {
    BuildContext? bottomSheetContext,
    List<Map<String, dynamic>>? prefetchedColors,
  }) async {
    final pickerContext = bottomSheetContext;
    final variantId = variant['id']?.toString();
    final colors =
        prefetchedColors ??
        (variantId == null || variantId.isEmpty
            ? const <Map<String, dynamic>>[]
            : await ProductVariantColorRepository.getForVariant(variantId));
    if (!mounted) {
      return;
    }
    if (pickerContext != null && !pickerContext.mounted) {
      return;
    }

    if (colors.isEmpty) {
      _closeVariantPicker(pickerContext);
      _addProductToCart(product, variant: variant);
      return;
    }

    if (colors.length == 1) {
      final onlyColor = colors.first;
      if (_variantColorOutOfStock(product, onlyColor)) {
        _showVariantColorUnavailableSnackBar(product, variant, onlyColor);
        return;
      }
      _closeVariantPicker(pickerContext);
      _addProductToCart(product, variant: variant, variantColor: onlyColor);
      return;
    }

    final categoryName = _categoryNameFor(
      product,
      ref.read(categoriesProvider).valueOrNull ??
          const <Map<String, dynamic>>[],
    );
    await ProductVariantDialog.show(
      pickerContext ?? context,
      product: product,
      variants: [variant],
      colorsByVariantId: {
        if (variantId != null && variantId.isNotEmpty) variantId: colors,
      },
      categoryName: categoryName,
      rememberedColorIdForVariant: (selectedVariant) =>
          _lastSelectedColorId(product, selectedVariant),
      onAddToCart: (selectedVariant, selectedColor, dialogContext) {
        if (selectedColor == null) {
          return;
        }
        if (_variantColorOutOfStock(product, selectedColor)) {
          _showVariantColorUnavailableSnackBar(
            product,
            selectedVariant,
            selectedColor,
          );
          return;
        }
        final added = _addProductToCart(
          product,
          variant: selectedVariant,
          variantColor: selectedColor,
        );
        if (added && dialogContext.mounted) {
          Navigator.pop(dialogContext);
        }
      },
    );
  }

  Future<void> _pickVariantForProduct(Map<String, dynamic> product) async {
    final variants = await ProductVariantRepository.getForProduct(
      product['id'] as String,
    );
    if (!mounted) {
      return;
    }
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This product has no variants yet.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final colors = await ProductVariantColorRepository.getForProduct(
      product['id'] as String,
    );
    if (!mounted) {
      return;
    }
    final colorsByVariantId = _colorsByVariantId(colors);

    final categoryName = _categoryNameFor(
      product,
      ref.read(categoriesProvider).valueOrNull ??
          const <Map<String, dynamic>>[],
    );
    await ProductVariantDialog.show(
      context,
      product: product,
      variants: variants,
      colorsByVariantId: colorsByVariantId,
      categoryName: categoryName,
      rememberedColorIdForVariant: (variant) =>
          _lastSelectedColorId(product, variant),
      onAddToCart: (variant, variantColor, dialogContext) {
        final variantId = variant['id']?.toString();
        final variantColors =
            colorsByVariantId[variantId] ?? const <Map<String, dynamic>>[];
        if (variantColors.isNotEmpty && variantColor == null) {
          return;
        }
        if (variantColor != null &&
            _variantColorOutOfStock(product, variantColor)) {
          _showVariantColorUnavailableSnackBar(product, variant, variantColor);
          return;
        }
        final added = _addProductToCart(
          product,
          variant: variant,
          variantColor: variantColor,
        );
        if (added && dialogContext.mounted) {
          Navigator.pop(dialogContext);
        }
      },
    );
  }

  Future<void> _handleProductSelection(Map<String, dynamic> product) async {
    final matchedSerial = _matchedSerialFromSearchResult(product);
    if (matchedSerial != null) {
      _addProductToCart(
        product,
        variant: _matchedVariantFromSearchResult(product),
        serialNumbers: [matchedSerial],
      );
      return;
    }

    final matchedVariant = _matchedVariantFromSearchResult(product);
    if (matchedVariant != null) {
      await _handleVariantSelection(product, matchedVariant);
      return;
    }

    if (!_isVariantProduct(product)) {
      _addProductToCart(product);
      return;
    }

    await _pickVariantForProduct(product);
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    final result = await ProductRepository.lookupBarcode(barcode);
    if (result == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('No product found with barcode: $barcode'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.warning,
            width: 360,
          ),
        );
      }
      return;
    }

    if (result['result_type'] == 'serial') {
      final serialNumber = result['serial_number']?.toString().trim() ?? '';
      final parentProduct = <String, dynamic>{
        'id': result['id'],
        'name': result['name'],
        'price': result['price'],
        'cost': result['cost'],
        'stock': result['stock'],
        'unit': result['unit'],
        'stock_unit': result['stock_unit'],
        'sale_unit': result['sale_unit'],
        'sale_to_stock_factor': result['sale_to_stock_factor'],
        'image_url': result['image_url'],
        'category_id': result['category_id'],
        'track_stock': result['track_stock'],
        'has_variants': result['has_variants'],
      };
      final variantId = result['variant_id']?.toString();
      final variant = variantId == null || variantId.isEmpty
          ? null
          : <String, dynamic>{
              'id': variantId,
              'product_id': result['id'],
              'name': result['variant_name'],
              'sku': result['variant_sku'],
              'barcode': result['variant_barcode'],
              'price': result['variant_price'],
              'cost': result['variant_cost'],
              'stock': result['variant_stock'],
              'low_stock': result['variant_low_stock'],
            };
      _addProductToCart(
        parentProduct,
        variant: variant,
        serialNumbers: [serialNumber.isEmpty ? barcode : serialNumber],
      );
      return;
    }

    if (result['result_type'] == 'variant') {
      final parentProduct = <String, dynamic>{
        'id': result['id'],
        'name': result['name'],
        'price': result['price'],
        'cost': result['cost'],
        'stock': result['stock'],
        'unit': result['unit'],
        'stock_unit': result['stock_unit'],
        'sale_unit': result['sale_unit'],
        'sale_to_stock_factor': result['sale_to_stock_factor'],
        'image_url': result['image_url'],
        'category_id': result['category_id'],
        'track_stock': result['track_stock'],
        'has_variants': result['has_variants'],
      };
      final variant = <String, dynamic>{
        'id': result['variant_id'],
        'product_id': result['id'],
        'name': result['variant_name'],
        'sku': result['variant_sku'],
        'barcode': result['variant_barcode'],
        'price': result['variant_price'],
        'cost': result['variant_cost'],
        'stock': result['variant_stock'],
        'low_stock': result['variant_low_stock'],
      };
      await _handleVariantSelection(parentProduct, variant);
      return;
    }

    await _handleProductSelection(result);
  }

  Future<void> _openCameraScanner() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode != null && barcode.isNotEmpty) {
      await _handleBarcodeScan(barcode);
    }
  }

  void _openServicesPage() {
    AppShell.selectIndex(11);
    AppShell.scaffoldKey.currentState?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final canUseProducts = SessionService.canUseProductPos;
    final canUseServices = SessionService.canUseServicePos;

    if (!canUseProducts && !canUseServices) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your admin has not enabled POS product or service access for this account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (!canUseProducts && canUseServices) {
      return _ServiceOnlyPosShortcut(onTap: _openServicesPage);
    }

    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(filteredProductsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final searchQuery = ref.watch(productSearchProvider);
    final viewMode = ref.watch(posProductViewModeProvider);
    final recentProducts = ref.watch(posRecentProductsProvider);
    final isMobileDevice = Platform.isAndroid || Platform.isIOS;

    final compact = MediaQuery.sizeOf(context).width <= 520;
    final baseProductPadding = compact ? 14.0 : 24.0;

    Widget serviceShortcut() {
      if (!canUseServices) {
        return const SizedBox.shrink();
      }
      return _PremiumIconAction(
        icon: Icons.design_services_outlined,
        tooltip: 'Open services',
        onTap: _openServicesPage,
        compact: compact,
        accent: Theme.of(context).colorScheme.secondary,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Product grid columns are based on the actual ProductSide width.
        final sideWidth = constraints.maxWidth;
        final gridColumns = sideWidth < 600
            ? 2
            : sideWidth < 900
            ? 3
            : 4;
        final tightVertical = constraints.maxHeight < (compact ? 330 : 380);
        final productPadding = tightVertical
            ? (compact ? 10.0 : 16.0)
            : baseProductPadding;
        final sectionGap = tightVertical
            ? (compact ? 10.0 : 14.0)
            : (compact ? 14.0 : 20.0);
        final showQuickPicks =
            searchQuery.trim().isEmpty && constraints.maxHeight >= 330;

        return Container(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkBackground
              : Theme.of(context).scaffoldBackgroundColor,
          padding: EdgeInsets.all(productPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar with scan button
              TrainingAnchor(
                id: 'pos.search',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? double.infinity : 560,
                              ),
                              child: _PremiumSearchField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                query: searchQuery,
                                compact: compact,
                                autofocus: Platform.isWindows,
                                onTap: _focusSearchField,
                                onChanged: (v) =>
                                    ref
                                            .read(
                                              productSearchProvider.notifier,
                                            )
                                            .state =
                                        v,
                                onSubmitted: (v) {
                                  final code = v.trim();
                                  final lower = code.toLowerCase();
                                  // Only attempt barcode lookup if it looks like a barcode
                                  // (not a URL or plain text search entry)
                                  if (code.length >= 4 &&
                                      !lower.startsWith('http') &&
                                      !lower.startsWith('www.') &&
                                      !lower.contains('://') &&
                                      RegExp(
                                        r'^[A-Za-z0-9._-]+$',
                                      ).hasMatch(code)) {
                                    _handleBarcodeScan(code);
                                  } else {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => _focusSearchField(),
                                        );
                                  }
                                },
                                onClear: _clearSearch,
                              ),
                            ),
                          ),
                        ),
                        if (canUseServices) ...[
                          SizedBox(
                            width: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          serviceShortcut(),
                        ],
                        SizedBox(
                          width: compact ? AppSpacing.sm : AppSpacing.md,
                        ),
                        const _PosViewModeToggle(),
                        if (isMobileDevice) ...[
                          SizedBox(
                            width: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          _PremiumIconAction(
                            icon: Icons.qr_code_scanner_rounded,
                            tooltip: 'Scan barcode',
                            onTap: _openCameraScanner,
                            compact: compact,
                            accent: AppColors.primaryLight,
                          ),
                        ],
                      ],
                    ),
                    if (Platform.isWindows) ...[
                      SizedBox(height: AppSpacing.xs),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _SearchStatusHint(
                          key: ValueKey(_searchFocusNode.hasFocus),
                          ready: _searchFocusNode.hasFocus,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: sectionGap),

              if (showQuickPicks)
                productsAsync.maybeWhen(
                  data: (products) {
                    final quickPicks = _mergeQuickPicks(
                      recentProducts,
                      products,
                    );
                    if (quickPicks.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: EdgeInsets.only(bottom: sectionGap),
                      child: _QuickPicksStrip(
                        products: quickPicks,
                        onTap: _handleProductSelection,
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),

              // Category chips
              TrainingAnchor(
                id: 'pos.categories',
                child: categoriesAsync.when(
                  data: (categories) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _CategoryChip(
                          title: 'All',
                          isSelected: selectedCategory == null,
                          onTap: () =>
                              ref
                                      .read(selectedCategoryProvider.notifier)
                                      .state =
                                  null,
                        ),
                        ...categories.map(
                          (cat) => _CategoryChip(
                            title: cat['name'] as String,
                            color: cat['color'] as String?,
                            categoryName: cat['name'] as String?,
                            isSelected: selectedCategory == cat['id'],
                            onTap: () =>
                                ref
                                        .read(selectedCategoryProvider.notifier)
                                        .state =
                                    cat['id'] as String,
                          ),
                        ),
                      ],
                    ),
                  ),
                  loading: () => SizedBox(
                    height: 40,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (e, _) => Text(
                    AppErrorMessage.from(
                      e,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                  ),
                ),
              ),
              SizedBox(height: sectionGap),

              // Product grid
              Expanded(
                child: TrainingAnchor(
                  id: 'pos.products',
                  child: productsAsync.when(
                    data: (products) {
                      final categories = categoriesAsync.valueOrNull ?? [];
                      if (products.isEmpty) {
                        if (searchQuery.trim().isNotEmpty) {
                          return _NoProductSearchResults(
                            query: searchQuery.trim(),
                            canUseServices: canUseServices,
                            canManageProducts: SessionService.canAccessFeature(
                              UserAccessProfile.featureProducts,
                            ),
                            onClearSearch: _clearSearch,
                            onCreateProduct: () =>
                                _openProductForm(initialSearch: searchQuery),
                            onOpenServices: _openServicesPage,
                          );
                        }
                        return EmptyStateWidget(
                          icon: Icons.inventory_2_outlined,
                          title: 'No products found',
                          subtitle: selectedCategory == null
                              ? 'Add products to start selling from this POS.'
                              : 'Try a different category or clear your filters.',
                        );
                      }
                      if (viewMode == PosProductViewMode.compact) {
                        return ListView.separated(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          itemCount: products.length,
                          separatorBuilder: (_, _) => SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return _CompactProductTile(
                              product: product,
                              categoryName: _categoryNameFor(
                                product,
                                categories,
                              ),
                              onTap: () async {
                                await _handleProductSelection(product);
                              },
                            );
                          },
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridColumns,
                          mainAxisExtent: 144,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing: AppSpacing.sm,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return _ProductCard(
                            product: product,
                            categoryName: _categoryNameFor(product, categories),
                            onTap: () async {
                              await _handleProductSelection(product);
                            },
                          );
                        },
                      );
                    },
                    loading: () => GridView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumns,
                        mainAxisExtent: 144,
                        crossAxisSpacing: AppSpacing.sm,
                        mainAxisSpacing: AppSpacing.sm,
                      ),
                      itemCount: 8,
                      itemBuilder: (_, _) => Container(
                        decoration: BoxDecoration(
                          color:
                              (Theme.of(context).brightness == Brightness.dark
                                      ? AppColors.darkSurfaceHighlight
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest)
                                  .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        AppErrorMessage.from(
                          e,
                          fallback: AppErrorMessage.loadFailed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PremiumSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final bool compact;
  final bool autofocus;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _PremiumSearchField({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.compact,
    required this.autofocus,
    required this.onTap,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        final hasQuery = query.trim().isNotEmpty;
        final active = hasFocus || hasQuery;

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 38,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceHighlight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active
                  ? (isDark
                        ? AppColors.darkAccent.withValues(alpha: 0.28)
                        : AppColors.primary.withValues(alpha: 0.28))
                  : (isDark
                        ? AppColors.darkBorder.withValues(alpha: 0.9)
                        : AppColors.border),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? (isDark ? AppColors.darkAccent : AppColors.primary)
                            .withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: AnimatedRotation(
                  turns: hasFocus ? -0.04 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.manage_search_rounded,
                    size: 17,
                    color: active
                        ? (isDark ? AppColors.darkAccent : AppColors.primary)
                        : (isDark
                              ? AppColors.darkTextMuted
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  onTap: onTap,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  cursorColor: isDark
                      ? AppColors.darkAccent
                      : Theme.of(context).colorScheme.secondary,
                  cursorWidth: 1.6,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: compact
                        ? 'Search or scan'
                        : 'Search or scan barcode',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.darkTextMuted
                          : Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.72),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: hasQuery
                    ? _SearchClearButton(
                        key: const ValueKey('clear-search'),
                        onTap: onClear,
                        compact: compact,
                      )
                    : SizedBox(
                        key: ValueKey('empty-search-action'),
                        width: AppSpacing.sm,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchClearButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const _SearchClearButton({
    super.key,
    required this.onTap,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Clear search',
      child: Padding(
        padding: const EdgeInsets.only(right: 7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            width: compact ? 28 : 30,
            height: compact ? 28 : 30,
            decoration: BoxDecoration(
              color:
                  (Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurface
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest)
                      .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color:
                    (Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : Theme.of(context).colorScheme.outline)
                        .withValues(alpha: 0.88),
              ),
            ),
            child: Icon(
              Icons.close_rounded,
              size: compact ? 16 : 17,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchStatusHint extends StatelessWidget {
  final bool ready;

  const _SearchStatusHint({super.key, required this.ready});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = ready
        ? (isDark
              ? AppColors.darkAccent
              : Theme.of(context).colorScheme.secondary)
        : (isDark
              ? AppColors.darkTextMuted
              : Theme.of(context).colorScheme.onSurfaceVariant);

    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: ready
                ? (isDark
                      ? AppColors.darkAccent
                      : Theme.of(context).colorScheme.secondary)
                : (isDark
                      ? AppColors.darkTextMuted.withValues(alpha: 0.56)
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.56)),
            shape: BoxShape.circle,
            boxShadow: ready
                ? [
                    BoxShadow(
                      color:
                          (isDark
                                  ? AppColors.darkAccent
                                  : Theme.of(context).colorScheme.secondary)
                              .withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        ),
        SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            ready
                ? 'Scanner ready. Keep scanning without clicking.'
                : 'Tap search once before using a barcode scanner.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark
                  ? color.withValues(alpha: ready ? 1.0 : 0.85)
                  : color.withValues(alpha: ready ? 0.9 : 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumIconAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool compact;
  final Color accent;

  const _PremiumIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.compact,
    required this.accent,
  });

  @override
  State<_PremiumIconAction> createState() => _PremiumIconActionState();
}

class _PremiumIconActionState extends State<_PremiumIconAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final size = widget.compact ? 38.0 : 40.0;
    final iconSize = widget.compact ? 18.0 : 19.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : (_hovered ? 1.03 : 1),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceHighlight
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: active
                          ? widget.accent.withValues(alpha: 0.5)
                          : (isDark ? AppColors.darkBorder : AppColors.border),
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    size: iconSize,
                    color: active
                        ? widget.accent
                        : (isDark
                              ? AppColors.darkTextMuted
                              : Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.86)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosViewModeToggle extends ConsumerWidget {
  const _PosViewModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(posProductViewModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceHighlight : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PosViewModeButton(
            icon: Icons.grid_view_rounded,
            tooltip: 'Card view',
            selected: mode == PosProductViewMode.cards,
            onTap: () => ref.read(posProductViewModeProvider.notifier).state =
                PosProductViewMode.cards,
          ),
          _PosViewModeButton(
            icon: Icons.view_list_rounded,
            tooltip: 'Compact view',
            selected: mode == PosProductViewMode.compact,
            onTap: () => ref.read(posProductViewModeProvider.notifier).state =
                PosProductViewMode.compact,
          ),
        ],
      ),
    );
  }
}

class _PosViewModeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _PosViewModeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: selected
                ? (Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkAccent
                          : AppColors.primary)
                      .withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            icon,
            size: 17,
            color: selected
                ? (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkAccent
                      : AppColors.primary)
                : (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextMuted
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.82)),
          ),
        ),
      ),
    );
  }
}

class _QuickPicksStrip extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final Future<void> Function(Map<String, dynamic> product) onTap;

  const _QuickPicksStrip({required this.products, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick picks',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final product = products[index];
              return _QuickPickChip(
                product: product,
                onTap: () => onTap(product),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QuickPickChip extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const _QuickPickChip({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = product['name'] as String? ?? 'Product';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoProductSearchResults extends StatelessWidget {
  final String query;
  final bool canUseServices;
  final bool canManageProducts;
  final VoidCallback onClearSearch;
  final VoidCallback onCreateProduct;
  final VoidCallback onOpenServices;

  const _NoProductSearchResults({
    required this.query,
    required this.canUseServices,
    required this.canManageProducts,
    required this.onClearSearch,
    required this.onCreateProduct,
    required this.onOpenServices,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 58,
              color: isDark
                  ? AppColors.darkTextMuted.withValues(alpha: 0.5)
                  : Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
            SizedBox(height: 14),
            Text(
              'No match for "$query"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: isDark ? AppColors.darkTextPrimary : null,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Clear the search, create a product, or check services.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onClearSearch,
                  icon: Icon(Icons.close_rounded, size: 18),
                  label: Text('Clear'),
                ),
                if (canManageProducts)
                  FilledButton.icon(
                    onPressed: onCreateProduct,
                    icon: Icon(Icons.add_box_outlined, size: 18),
                    label: Text('Create Product'),
                  ),
                if (canUseServices)
                  OutlinedButton.icon(
                    onPressed: onOpenServices,
                    icon: Icon(Icons.design_services_outlined, size: 18),
                    label: Text('Services'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final VoidCallback onTap;

  const _CompactProductTile({
    required this.product,
    required this.categoryName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isVariantResult =
        product['result_type'] == 'variant' &&
        product['matched_variant_id'] != null;
    final variantName = product['matched_variant_name'] as String?;
    final name = isVariantResult && variantName?.trim().isNotEmpty == true
        ? '${product['name']} - ${variantName!.trim()}'
        : product['name'] as String? ?? 'Product';
    final price = isVariantResult
        ? (product['matched_variant_price'] as num? ??
                  product['price'] as num? ??
                  0)
              .toDouble()
        : (product['price'] as num? ?? 0).toDouble();
    final stock = isVariantResult
        ? (product['matched_variant_stock'] as num? ?? 0).toDouble()
        : (product['stock'] as num? ?? 0).toDouble();
    final lowStock = isVariantResult
        ? (product['matched_variant_low_stock'] as num? ?? 5).toDouble()
        : (product['low_stock'] as num? ?? 5).toDouble();
    final saleUnit = UnitUtils.saleUnitForProduct(product);
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final saleToStockFactor = UnitUtils.saleToStockFactor(product);
    final tracksStock = UnitUtils.tracksStock(product);
    final saleStock = saleToStockFactor > 0
        ? (stock / saleToStockFactor)
        : stock;
    final isLowStock = tracksStock && stock <= lowStock;
    final isOutOfStock = tracksStock && stock <= 0;
    final stockColor = isOutOfStock
        ? AppColors.error
        : isLowStock
        ? AppColors.warning
        : AppColors.success;
    final stockText = !tracksStock
        ? 'No stock limit'
        : isOutOfStock
        ? 'Out of stock'
        : UnitUtils.formatWithUnit(saleStock, saleUnit);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? AppColors.darkSurface
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: isOutOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Opacity(
          opacity: isOutOfStock ? 0.62 : 1,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
            child: Row(
              children: [
                _ProductImagePlaceholder(
                  categoryName: categoryName,
                  isOutOfStock: isOutOfStock,
                  size: 42,
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? AppColors.darkTextPrimary : null,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        categoryName ?? 'General',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (saleUnit != stockUnit) ...[
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          'Stocked: ${UnitUtils.formatWithUnit(stock, stockUnit)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${ShopSettings.currency}${price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkAccentSoft
                            : AppColors.success,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: stockColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Text(
                        stockText,
                        style: TextStyle(
                          color: stockColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.add_circle_rounded,
                  color: isOutOfStock
                      ? (isDark
                            ? AppColors.darkTextMuted
                            : Theme.of(context).colorScheme.onSurfaceVariant)
                      : (isDark
                            ? AppColors.darkAccent
                            : AppColors.primaryLight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceOnlyPosShortcut extends StatelessWidget {
  final VoidCallback onTap;

  const _ServiceOnlyPosShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color:
                      (isDark
                              ? AppColors.darkAccent
                              : Theme.of(context).colorScheme.secondary)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(
                  Icons.design_services_outlined,
                  color: isDark
                      ? AppColors.darkAccent
                      : Theme.of(context).colorScheme.secondary,
                  size: 28,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'Services are managed on the Services page',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.darkTextPrimary : null,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Open Services to create orders, quick-sell jobs, and send service charges to the cart.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onTap,
                icon: Icon(Icons.open_in_new, size: 18),
                label: Text('Open Services'),
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? AppColors.darkAccent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────── RIGHT SIDE: Cart ────────────────

class _CartSide extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final tax = ref.watch(cartTaxProvider);
    final discount = ref.watch(discountProvider);
    final appliedPromotions = ref.watch(appliedPromotionsProvider);
    final total = ref.watch(cartTotalProvider);
    final convertedTotal = ExchangeRateRepository.formatConverted(total);
    final canViewProfit = SessionService.canAccessFeature(
      UserAccessProfile.featureProfitLoss,
    );
    final profit = canViewProfit ? ref.watch(cartProfitProvider) : 0.0;
    final heldSalesAsync = ref.watch(heldSalesProvider);
    final heldSaleCount = heldSalesAsync.valueOrNull?.length ?? 0;
    final currentShiftAsync = ref.watch(currentShiftProvider);
    final currentShift = currentShiftAsync.valueOrNull;
    final currentSummaryAsync = ref.watch(currentShiftSummaryProvider);
    final currentSummary = currentSummaryAsync.valueOrNull;
    final hasOpenShift = currentShift != null;
    final requiresManagedShift = ShiftRepository.roleRequiresManagedShift(
      SessionService.currentUserRole,
    );
    ref.listen(pikiNavigateProvider, (_, next) {
      if (next != PikiNavTarget.pos) return;
      ref.read(pikiNavigateProvider.notifier).state = PikiNavTarget.none;
      if (ref.read(cartProvider).isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _processCheckout(context, ref);
        }
      });
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileCart =
            MediaQuery.sizeOf(context).width <= 430 ||
            constraints.maxWidth <= 430;

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          color: isDark
              ? AppColors.darkSurface
              : Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Current Sale',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (heldSalesAsync.isLoading)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          TextButton.icon(
                            onPressed: () => _showHeldSalesDialog(context, ref),
                            icon: Icon(
                              heldSaleCount > 0
                                  ? Icons.pause_circle_filled_outlined
                                  : Icons.pause_circle_outline,
                              size: 18,
                              color: heldSaleCount > 0
                                  ? AppColors.primaryLight
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            label: Text(
                              heldSaleCount > 0
                                  ? 'Held ($heldSaleCount)'
                                  : 'Held',
                            ),
                          ),
                        if (cart.isNotEmpty) ...[
                          SizedBox(width: AppSpacing.sm),
                          TextButton.icon(
                            onPressed: () => _clearCurrentSale(ref),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.error,
                            ),
                            label: Text(
                              'Clear',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isMobileCart ? 9 : AppSpacing.md),
                      decoration: BoxDecoration(
                        color: hasOpenShift
                            ? AppColors.success.withValues(alpha: 0.10)
                            : AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          isMobileCart ? AppRadius.sm : AppRadius.md,
                        ),
                        border: Border.all(
                          color: hasOpenShift
                              ? AppColors.success.withValues(alpha: 0.25)
                              : AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasOpenShift
                                ? Icons.timer_rounded
                                : Icons.lock_clock_outlined,
                            color: hasOpenShift
                                ? AppColors.success
                                : AppColors.warning,
                            size: isMobileCart ? 17 : 24,
                          ),
                          SizedBox(
                            width: isMobileCart ? AppSpacing.sm : AppSpacing.md,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasOpenShift
                                      ? 'Shift is open'
                                      : currentShiftAsync.isLoading
                                      ? 'Checking shift status...'
                                      : requiresManagedShift
                                      ? 'No shift open yet'
                                      : 'Shift is optional',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: isMobileCart ? 12 : null,
                                  ),
                                ),
                                if (!isMobileCart) ...[
                                  SizedBox(height: AppSpacing.xs),
                                  Text(
                                    hasOpenShift
                                        ? 'Expected cash: ${ShopSettings.currency}${((currentSummary?['expected_cash'] as num?) ?? 0).toStringAsFixed(2)}'
                                        : requiresManagedShift
                                        ? 'The first cash transaction will auto-open a shift. Kopesha credit sales can continue now.'
                                        : 'Open a shift only when you want drawer tracking for this session.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          (hasOpenShift
                                                  ? AppColors.success
                                                  : AppColors.warning)
                                              .withValues(alpha: 0.95),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!hasOpenShift && !currentShiftAsync.isLoading)
                            TextButton(
                              onPressed: () => AppShell.selectIndex(10),
                              style: TextButton.styleFrom(
                                visualDensity: isMobileCart
                                    ? VisualDensity.compact
                                    : VisualDensity.standard,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobileCart
                                      ? AppSpacing.xs
                                      : AppSpacing.sm,
                                  vertical: isMobileCart
                                      ? AppSpacing.xs
                                      : AppSpacing.sm,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                requiresManagedShift
                                    ? isMobileCart
                                          ? 'Open'
                                          : 'Open Manually'
                                    : 'Go to Shifts',
                                style: TextStyle(
                                  fontSize: isMobileCart ? 12 : 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              Expanded(
                child: cart.isEmpty
                    ? _buildEmptyCartState(
                        context,
                        ref,
                        heldSaleCount: heldSaleCount,
                        holdsLoading: heldSalesAsync.isLoading,
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(
                          isMobileCart ? AppSpacing.md : AppSpacing.lg,
                        ),
                        itemCount: cart.length,
                        separatorBuilder: (_, _) => isMobileCart
                            ? SizedBox(height: AppSpacing.sm)
                            : Divider(height: AppSpacing.xxl),
                        itemBuilder: (context, index) {
                          final item = cart[index];
                          return _CartItemRow(
                            item: item,
                            showProfit: canViewProfit,
                          );
                        },
                      ),
              ),
              if (cart.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(
                    isMobileCart ? AppSpacing.sm : AppSpacing.xxl,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  child: isMobileCart
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _CompactCartAmount(
                                    label: 'Total',
                                    value:
                                        '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                                    valueColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    isPrimary: true,
                                  ),
                                ),
                                if (canViewProfit) ...[
                                  SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: _CompactCartAmount(
                                      label: 'Profit',
                                      value:
                                          '${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                                      valueColor: AppColors.success,
                                    ),
                                  ),
                                ],
                                SizedBox(width: AppSpacing.sm),
                                SizedBox(
                                  height: 40,
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _processCheckout(context, ref),
                                    icon: Icon(Icons.payment, size: 16),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Pay ${ShopSettings.currency}${total.toStringAsFixed(2)}',
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                      ),
                                      backgroundColor: AppColors.primary,
                                      textStyle: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (convertedTotal.isNotEmpty) ...[
                              SizedBox(height: AppSpacing.xs),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Also $convertedTotal',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ),
                            ],
                            if (discount > 0 || tax > 0) ...[
                              SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Subtotal ${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (tax > 0)
                                    Text(
                                      'Tax ${ShopSettings.currency}${tax.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  if (discount > 0) ...[
                                    SizedBox(width: AppSpacing.sm),
                                    Text(
                                      '-${ShopSettings.currency}${discount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 11,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            if (appliedPromotions.isNotEmpty) ...[
                              SizedBox(height: AppSpacing.xs),
                              _PromotionBreakdown(
                                promotions: appliedPromotions,
                                compact: true,
                              ),
                            ],
                            SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showDiscountDialog(
                                      context,
                                      ref,
                                      subtotal,
                                    ),
                                    icon: Icon(
                                      Icons.local_offer_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      discount > 0
                                          ? 'Edit Discount'
                                          : 'Discount',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.sm,
                                      ),
                                      textStyle: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                if (discount > 0) ...[
                                  SizedBox(width: AppSpacing.sm),
                                  IconButton(
                                    tooltip: 'Clear discount',
                                    onPressed: () {
                                      ref
                                              .read(discountProvider.notifier)
                                              .state =
                                          0;
                                      ref
                                              .read(
                                                appliedPromotionsProvider
                                                    .notifier,
                                              )
                                              .state =
                                          const [];
                                    },
                                    icon: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _holdCurrentSale(context, ref),
                                    icon: Icon(
                                      Icons.pause_circle_outline,
                                      size: 16,
                                    ),
                                    label: Text('Hold'),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.sm,
                                      ),
                                      textStyle: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: heldSalesAsync.isLoading
                                        ? null
                                        : () => _showHeldSalesDialog(
                                            context,
                                            ref,
                                          ),
                                    icon: Icon(Icons.layers_outlined, size: 16),
                                    label: Text(
                                      heldSaleCount > 0
                                          ? 'Held ($heldSaleCount)'
                                          : 'Held',
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.sm,
                                      ),
                                      textStyle: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _SummaryRow(
                              title: 'Subtotal',
                              value:
                                  '${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
                            ),
                            SizedBox(height: AppSpacing.sm),
                            _SummaryRow(
                              title: 'Tax (${ShopSettings.taxRate}%)',
                              value:
                                  '${ShopSettings.currency}${tax.toStringAsFixed(2)}',
                            ),
                            if (discount > 0) ...[
                              SizedBox(height: AppSpacing.sm),
                              _SummaryRow(
                                title: 'Discount',
                                value:
                                    '-${ShopSettings.currency}${discount.toStringAsFixed(2)}',
                                isDiscount: true,
                              ),
                              if (appliedPromotions.isNotEmpty) ...[
                                SizedBox(height: AppSpacing.xs),
                                _PromotionBreakdown(
                                  promotions: appliedPromotions,
                                ),
                              ],
                            ],
                            SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showDiscountDialog(
                                      context,
                                      ref,
                                      subtotal,
                                    ),
                                    icon: Icon(Icons.local_offer_outlined),
                                    label: Text(
                                      discount > 0
                                          ? 'Edit Discount'
                                          : 'Add Discount / Promo',
                                    ),
                                  ),
                                ),
                                if (discount > 0) ...[
                                  SizedBox(width: AppSpacing.md),
                                  TextButton.icon(
                                    onPressed: () {
                                      ref
                                              .read(discountProvider.notifier)
                                              .state =
                                          0;
                                      ref
                                              .read(
                                                appliedPromotionsProvider
                                                    .notifier,
                                              )
                                              .state =
                                          const [];
                                    },
                                    icon: Icon(Icons.close, size: 18),
                                    label: Text('Clear'),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: AppSpacing.lg),
                            Divider(),
                            SizedBox(height: AppSpacing.lg),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                SizedBox(width: AppSpacing.md),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                                        textAlign: TextAlign.end,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      if (convertedTotal.isNotEmpty)
                                        Text(
                                          convertedTotal,
                                          textAlign: TextAlign.end,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (canViewProfit) ...[
                              SizedBox(height: AppSpacing.sm),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Profit',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  SizedBox(width: AppSpacing.md),
                                  Flexible(
                                    child: Text(
                                      '${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                                      textAlign: TextAlign.end,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _holdCurrentSale(context, ref),
                                    icon: Icon(Icons.pause_circle_outline),
                                    label: Text('Hold Sale'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.lg,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: heldSalesAsync.isLoading
                                        ? null
                                        : () => _showHeldSalesDialog(
                                            context,
                                            ref,
                                          ),
                                    icon: Icon(Icons.layers_outlined),
                                    label: Text(
                                      heldSaleCount > 0
                                          ? 'Held Orders ($heldSaleCount)'
                                          : 'Held Orders',
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.lg,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (heldSaleCount > 0) ...[
                              SizedBox(height: AppSpacing.sm),
                              Text(
                                'You have $heldSaleCount held sale${heldSaleCount == 1 ? '' : 's'} ready to resume.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.85),
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            SizedBox(height: AppSpacing.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _processCheckout(context, ref),
                                    icon: Icon(Icons.payment),
                                    label: Text(
                                      'Checkout • ${ShopSettings.currency}${total.toStringAsFixed(2)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.lg,
                                      ),
                                      backgroundColor: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: AppSpacing.sm),
                            Text(
                              'Select a payment method such as Cash, Kopesha, or Mobile Money during checkout.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyCartState(
    BuildContext context,
    WidgetRef ref, {
    required int heldSaleCount,
    required bool holdsLoading,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final todayStatsAsync = ref.watch(posTodayStatsProvider);
    final recentSalesAsync = ref.watch(posRecentSalesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Empty cart headline
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder.withValues(alpha: 0.6)
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.shopping_basket_outlined,
                  size: 48,
                  color: isDark
                      ? AppColors.darkTextMuted.withValues(alpha: 0.5)
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  'Your cart is empty',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Tap products to add them to your sale.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.xl),
          // Today's quick stats
          Text(
            'Today\'s Performance',
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextPrimary
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          todayStatsAsync.when(
            data: (stats) {
              final salesCount = (stats['total_sales'] as num?)?.toInt() ?? 0;
              final revenue =
                  (stats['total_revenue'] as num?)?.toDouble() ?? 0.0;
              final itemsSold = (stats['total_items'] as num?)?.toInt() ?? 0;
              return Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Today Sales',
                      value: '$salesCount',
                      icon: Icons.receipt_long_outlined,
                      isDark: isDark,
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatCard(
                      label: 'Items Sold',
                      value: '$itemsSold',
                      icon: Icons.shopping_bag_outlined,
                      accent: AppColors.success,
                      isDark: isDark,
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatCard(
                      label: 'Revenue',
                      value:
                          '${ShopSettings.currency}${revenue.toStringAsFixed(0)}',
                      icon: Icons.payments_outlined,
                      accent: AppColors.darkAccentSoft,
                      isDark: isDark,
                    ),
                  ),
                ],
              );
            },
            loading: () => Row(
              children: [
                Expanded(child: _StatCardSkeleton(isDark: isDark)),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: _StatCardSkeleton(isDark: isDark)),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: _StatCardSkeleton(isDark: isDark)),
              ],
            ),
            error: (_, _) => Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Today Sales',
                    value: '—',
                    icon: Icons.receipt_long_outlined,
                    isDark: isDark,
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatCard(
                    label: 'Items Sold',
                    value: '—',
                    icon: Icons.shopping_bag_outlined,
                    isDark: isDark,
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatCard(
                    label: 'Revenue',
                    value: '—',
                    icon: Icons.payments_outlined,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.xxl),
          // Recent sales
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Sales',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextButton(
                onPressed: () => AppShell.selectIndex(4),
                child: Text(
                  'View All',
                  style: TextStyle(
                    color: isDark ? AppColors.darkAccent : null,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          recentSalesAsync.when(
            data: (sales) {
              if (sales.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.4)
                        : Theme.of(context).colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.5)
                          : Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'No recent sales. Complete your first sale to see it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              final recent = sales.take(5).toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: recent.asMap().entries.map((entry) {
                  final sale = entry.value;
                  final total = (sale['total_amount'] as num? ?? 0).toDouble();
                  final paymentType = sale['payment_type'] as String? ?? 'Cash';
                  final createdAt = sale['created_at'] as String?;
                  final productNames = sale['product_names'] as String?;
                  final serviceNames = sale['service_names'] as String?;
                  final itemsLabel = _formatRecentSaleItems(
                    productNames,
                    serviceNames,
                  );
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == recent.length - 1
                          ? 0
                          : AppSpacing.sm,
                    ),
                    child: _RecentSaleRow(
                      paymentType: paymentType,
                      total:
                          '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                      time: _formatRecentSaleTime(createdAt),
                      items: itemsLabel,
                      isDark: isDark,
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (index) => Padding(
                  padding: EdgeInsets.only(
                    bottom: index == 2 ? 0 : AppSpacing.sm,
                  ),
                  child: _RecentSaleRowSkeleton(isDark: isDark),
                ),
              ),
            ),
            error: (_, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.4)
                    : Theme.of(context).colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                'Could not load recent sales.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (heldSaleCount > 0) ...[
            SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showHeldSalesDialog(context, ref),
              icon: Icon(Icons.layers_outlined),
              label: Text('Resume Held Sale ($heldSaleCount)'),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? AppColors.darkAccent : null,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _applyActivePromotions(
    WidgetRef ref,
    List<CartItem> cart,
  ) async {
    final signature = _cartPromotionSignature(cart);
    if (cart.isEmpty) {
      ref.read(appliedPromotionsProvider.notifier).state = const [];
      ref.read(discountProvider.notifier).state = 0;
      return;
    }
    try {
      final result = await PromotionRepository.evaluateCart(cart);
      if (_cartPromotionSignature(ref.read(cartProvider)) != signature) {
        return;
      }
      ref.read(appliedPromotionsProvider.notifier).state =
          result.appliedPromotions;
      ref.read(discountProvider.notifier).state = result.amount;
    } catch (_) {
      if (_cartPromotionSignature(ref.read(cartProvider)) != signature) {
        return;
      }
      ref.read(appliedPromotionsProvider.notifier).state = const [];
    }
  }

  static String _cartPromotionSignature(List<CartItem> cart) {
    return cart
        .map(
          (item) =>
              '${item.cartKey}:${item.quantity.toStringAsFixed(3)}:${item.unitPrice.toStringAsFixed(2)}',
        )
        .join('|');
  }

  String _formatRecentSaleItems(String? products, String? services) {
    final parts = <String>[
      if (products != null && products.trim().isNotEmpty) products.trim(),
      if (services != null && services.trim().isNotEmpty) services.trim(),
    ];
    if (parts.isEmpty) return 'Sale completed';
    final combined = parts.join(', ');
    if (combined.length <= 32) return combined;
    return '${combined.substring(0, 32).trim()}...';
  }

  String _formatRecentSaleTime(String? createdAt) {
    if (createdAt == null) return 'Earlier';
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return 'Earlier';
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static Future<void> _showDiscountDialog(
    BuildContext context,
    WidgetRef ref,
    double subtotal,
  ) async {
    final controller = TextEditingController();
    var mode = 'amount';
    final currentDiscount = ref.read(discountProvider);
    if (currentDiscount > 0) {
      controller.text = currentDiscount.toStringAsFixed(2);
    }

    final discount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Discount / Promotion'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'amount',
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Amount'),
                    ),
                    ButtonSegment(
                      value: 'percent',
                      icon: Icon(Icons.percent_outlined),
                      label: Text('Percent'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (values) =>
                      setDialogState(() => mode = values.first),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: mode == 'amount'
                        ? 'Discount amount'
                        : 'Discount %',
                    prefixText: mode == 'amount' ? ShopSettings.currency : '',
                    suffixText: mode == 'percent' ? '%' : '',
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Subtotal: ${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 0.0),
              child: Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value =
                    double.tryParse(controller.text.trim())?.abs() ?? 0;
                final computed = mode == 'percent'
                    ? subtotal * (value.clamp(0, 100) / 100)
                    : value;
                Navigator.pop(
                  dialogContext,
                  computed.clamp(0, subtotal).toDouble(),
                );
              },
              child: Text('Apply'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (discount == null) {
      return;
    }
    ref.read(discountProvider.notifier).state = discount;
  }

  Future<void> _showHeldSalesDialog(
    BuildContext parentContext,
    WidgetRef parentRef,
  ) async {
    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 620),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(dialogContext).colorScheme.outline,
              ),
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final heldSalesAsync = ref.watch(heldSalesProvider);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Held Orders',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Resume or discard saved carts.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.85),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1),
                    Expanded(
                      child: heldSalesAsync.when(
                        loading: () =>
                            Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  size: 40,
                                  color: AppColors.warning,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Could not load held orders.',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  AppErrorMessage.from(
                                    error,
                                    fallback: AppErrorMessage.loadFailed,
                                  ),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      ref.invalidate(heldSalesProvider),
                                  icon: Icon(Icons.refresh),
                                  label: Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        data: (heldSales) {
                          if (heldSales.isEmpty) {
                            return const EmptyStateWidget(
                              icon: Icons.layers_clear_outlined,
                              title: 'No held orders',
                              subtitle:
                                  'Carts you put on hold will appear here.',
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: heldSales.length,
                            separatorBuilder: (_, _) => SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final hold = heldSales[index];
                              final holdId = hold['id'] as String? ?? '';
                              final holdName =
                                  hold['name'] as String? ?? 'Held Sale';

                              return _HeldSaleCard(
                                hold: hold,
                                onResume: () async {
                                  Navigator.of(dialogContext).pop();
                                  await _resumeHeldSale(
                                    parentContext,
                                    parentRef,
                                    holdId: holdId,
                                  );
                                },
                                onDiscard: () async {
                                  final confirmed =
                                      await _confirmDeleteHeldSale(
                                        context,
                                        holdName,
                                      );
                                  if (!context.mounted || !confirmed) {
                                    return;
                                  }

                                  try {
                                    await HeldSaleRepository.deleteHold(holdId);
                                    ref.invalidate(heldSalesProvider);
                                    if (parentContext.mounted) {
                                      _showSnackBar(
                                        parentContext,
                                        '$holdName was discarded.',
                                        backgroundColor: AppColors.warning,
                                      );
                                    }
                                  } catch (error) {
                                    if (parentContext.mounted) {
                                      _showSnackBar(
                                        parentContext,
                                        AppErrorMessage.withContext(
                                          error,
                                          prefix:
                                              'Could not discard held sale.',
                                          fallback:
                                              'Could not discard this held sale. Please try again.',
                                        ),
                                        backgroundColor: AppColors.error,
                                      );
                                    }
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _holdCurrentSale(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      return;
    }

    final enteredName = await _showHoldNameDialog(context, cart);
    if (!context.mounted || enteredName == null) {
      return;
    }

    final holdName = enteredName.trim().isEmpty
        ? _defaultHoldName(cart)
        : enteredName.trim();

    try {
      await HeldSaleRepository.createHold(
        name: holdName,
        subtotal: ref.read(cartSubtotalProvider),
        tax: ref.read(cartTaxProvider),
        discount: ref.read(discountProvider),
        total: ref.read(cartTotalProvider),
        userId: SessionService.currentUserId.isNotEmpty
            ? SessionService.currentUserId
            : 'admin',
        cashierName: SessionService.currentUserName,
        items: cart.map((item) => item.toHeldItem()).toList(),
      );

      _clearCurrentSale(ref);
      ref.invalidate(heldSalesProvider);

      if (context.mounted) {
        _showSnackBar(
          context,
          '$holdName saved to held orders.',
          backgroundColor: AppColors.primaryLight,
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(
          context,
          AppErrorMessage.withContext(
            error,
            prefix: 'Could not hold this sale.',
            fallback: 'Could not hold this sale. Please try again.',
          ),
          backgroundColor: AppColors.error,
        );
      }
    }
  }

  Future<void> _resumeHeldSale(
    BuildContext context,
    WidgetRef ref, {
    required String holdId,
  }) async {
    if (holdId.trim().isEmpty) {
      return;
    }

    final currentCart = ref.read(cartProvider);
    if (currentCart.isNotEmpty) {
      final shouldReplace = await _confirmReplaceCurrentSale(context);
      if (!context.mounted || !shouldReplace) {
        return;
      }
    }

    try {
      final heldSale = await HeldSaleRepository.takeHold(holdId);
      ref.invalidate(heldSalesProvider);

      if (!context.mounted) {
        return;
      }
      if (heldSale == null) {
        _showSnackBar(
          context,
          'That held sale could not be found anymore.',
          backgroundColor: AppColors.warning,
        );
        return;
      }

      final items = List<Map<String, dynamic>>.from(
        heldSale['items'] as List<dynamic>? ?? const <Map<String, dynamic>>[],
      );
      final adjustments =
          (heldSale['adjustments'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .toList();
      final holdName = heldSale['name'] as String? ?? 'Held Sale';

      if (items.isEmpty) {
        final message = adjustments.isEmpty
            ? '$holdName has no available items to restore.'
            : '$holdName has no available items to restore. ${adjustments.first}';
        _showSnackBar(context, message, backgroundColor: AppColors.warning);
        return;
      }

      _clearCurrentSale(ref);
      ref.read(cartProvider.notifier).restoreHeldItems(items);
      ref.read(discountProvider.notifier).state = _asDouble(
        heldSale['discount'],
      );

      final message = adjustments.isEmpty
          ? '$holdName restored to the cart.'
          : '$holdName restored with ${adjustments.length} adjustment(s). ${adjustments.first}';
      _showSnackBar(
        context,
        message,
        backgroundColor: adjustments.isEmpty
            ? AppColors.success
            : AppColors.warning,
      );
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(
          context,
          AppErrorMessage.withContext(
            error,
            prefix: 'Could not resume held sale.',
            fallback: 'Could not resume this held sale. Please try again.',
          ),
          backgroundColor: AppColors.error,
        );
      }
    }
  }

  void _clearCurrentSale(WidgetRef ref) {
    ref.read(cartProvider.notifier).clear();
    ref.read(discountProvider.notifier).state = 0;
    ref.read(appliedPromotionsProvider.notifier).state = const [];
  }

  Future<String?> _showHoldNameDialog(
    BuildContext context,
    List<CartItem> cart,
  ) async {
    final controller = TextEditingController(text: _defaultHoldName(cart));

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.pause_circle_outline, color: AppColors.primaryLight),
            SizedBox(width: 10),
            Text('Hold Current Sale'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Hold name',
            helperText: 'Use a short name so you can find it quickly later.',
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text),
            icon: Icon(Icons.save_outlined),
            label: Text('Save Hold'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<bool> _confirmReplaceCurrentSale(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Replace Current Cart?'),
        content: Text(
          'Resuming a held sale will replace the items currently in the cart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Current Cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Replace Cart'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<bool> _confirmDeleteHeldSale(
    BuildContext context,
    String holdName,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Discard Held Sale?'),
        content: Text(
          'Delete "$holdName" from held orders? This will not affect completed sales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Discard'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<Map<String, dynamic>?> _requireOpenShift(BuildContext context) async {
    final userId = currentShiftActorId();
    final role = SessionService.currentUserRole;
    final cashierName = ShiftRepository.normalizeActorName(
      SessionService.currentUserName,
    );
    final access = await ShiftRepository.resolveCurrentShift(userId: userId);
    if (access.autoClosedShift != null && context.mounted) {
      _showSnackBar(
        context,
        'Your previous-day shift was auto-closed before this cash transaction.',
        backgroundColor: AppColors.warning,
      );
    }
    if (access.currentShift != null ||
        !ShiftRepository.roleRequiresManagedShift(role)) {
      return access.currentShift;
    }
    if (!context.mounted) {
      return null;
    }

    final suggestedOpeningCash =
        await ShiftPreferencesService.getLastOpeningCash(userId);
    if (!context.mounted) {
      return null;
    }

    final opening = await showShiftAutoOpenDialog(
      context,
      transactionLabel: 'cash sale',
      suggestedOpeningCash: suggestedOpeningCash,
    );
    if (!context.mounted || opening == null) {
      return null;
    }

    final shift = await ShiftRepository.openShift(
      userId: userId,
      cashierName: cashierName,
      openingCash: opening.openingCash,
      note: opening.note ?? 'Auto-opened on first cash transaction.',
    );
    await ShiftPreferencesService.saveLastOpeningCash(
      userId,
      opening.openingCash,
    );
    if (context.mounted) {
      _showSnackBar(
        context,
        'A new shift was auto-opened for this cash transaction.',
        backgroundColor: AppColors.success,
      );
    }
    return shift;
  }

  Future<void> _processCheckout(BuildContext context, WidgetRef ref) async {
    final total = ref.read(cartTotalProvider);
    final pendingQuotationId = ref.read(activeQuotationIdProvider);

    void clearPendingQuotation() {
      if (pendingQuotationId != null && pendingQuotationId.isNotEmpty) {
        ref.read(activeQuotationIdProvider.notifier).state = null;
      }
    }

    final checkoutResult = await PaymentCheckoutDialog.show(
      context,
      total: total,
    );

    if (!context.mounted || checkoutResult == null) {
      clearPendingQuotation();
      return;
    }

    final type = checkoutResult['type'] as String;
    final customer = checkoutResult['customer'] as Map<String, dynamic>?;
    final dueDate = checkoutResult['dueDate'] as String?;
    final loyaltyLedgerId = checkoutResult['loyaltyLedgerId'] as String?;
    final loyaltyPoints = checkoutResult['loyaltyPoints'] as int?;
    final giftCardId = checkoutResult['giftCardId'] as String?;
    final giftCardCode = checkoutResult['giftCardCode'] as String?;
    final giftCardAmount = (checkoutResult['giftCardAmount'] as num?)
        ?.toDouble();
    final giftCardBalanceAfter =
        (checkoutResult['giftCardBalanceAfter'] as num?)?.toDouble();

    if (type == 'kopesha') {
      // Kopesha payment - requires customer
      if (customer == null) {
        _showSnackBar(
          context,
          'Customer is required for Kopesha',
          backgroundColor: AppColors.error,
        );
        clearPendingQuotation();
        return;
      }

      await _completeSale(
        context,
        ref,
        paymentType: 'kopesha',
        isCredit: true,
        isCashDrawer: false,
        customerId: customer['id'] as String?,
        customerName: customer['name'] as String?,
        dueDate: dueDate,
        convertFromQuotationId: pendingQuotationId,
        loyaltyLedgerId: loyaltyLedgerId,
        loyaltyPoints: loyaltyPoints,
        giftCardId: giftCardId,
        giftCardCode: giftCardCode,
        giftCardAmount: giftCardAmount,
        giftCardBalanceAfter: giftCardBalanceAfter,
      );
    } else if (type == 'mpesa') {
      final phoneNumber = checkoutResult['phoneNumber'] as String?;
      if (phoneNumber == null || phoneNumber.trim().isEmpty) {
        _showSnackBar(
          context,
          'M-Pesa phone number is required',
          backgroundColor: AppColors.error,
        );
        clearPendingQuotation();
        return;
      }
      await _completeMpesaCheckout(
        context,
        ref,
        phoneNumber: phoneNumber,
        customer: customer,
        convertFromQuotationId: pendingQuotationId,
        loyaltyLedgerId: loyaltyLedgerId,
        loyaltyPoints: loyaltyPoints,
        giftCardId: giftCardId,
        giftCardCode: giftCardCode,
        giftCardAmount: giftCardAmount,
        giftCardBalanceAfter: giftCardBalanceAfter,
      );
    } else if (type == 'mpesa_manual') {
      final payment = checkoutResult['payment'];
      if (payment is! PosPayment || !payment.isPaid) {
        _showSnackBar(
          context,
          'M-Pesa payment is not confirmed yet. Sale was not saved.',
          backgroundColor: AppColors.warning,
        );
        clearPendingQuotation();
        return;
      }
      await _completeManualMpesaCheckout(
        context,
        ref,
        payment: payment,
        customer: customer,
        convertFromQuotationId: pendingQuotationId,
        loyaltyLedgerId: loyaltyLedgerId,
        loyaltyPoints: loyaltyPoints,
        giftCardId: giftCardId,
        giftCardCode: giftCardCode,
        giftCardAmount: giftCardAmount,
        giftCardBalanceAfter: giftCardBalanceAfter,
      );
    } else {
      // Other payment methods
      final paymentMethod =
          checkoutResult['paymentMethod'] as Map<String, dynamic>?;
      if (paymentMethod == null) {
        clearPendingQuotation();
        return;
      }

      final isCashDrawer =
          PaymentMethodRepository.providerKeyFor(paymentMethod) ==
          PaymentMethodRepository.providerCash;
      final paymentName = paymentMethod['name'] as String;

      if (isCashDrawer) {
        final shift = await _requireOpenShift(context);
        final requiresManagedShift = ShiftRepository.roleRequiresManagedShift(
          SessionService.currentUserRole,
        );
        if (!context.mounted || (requiresManagedShift && shift == null)) {
          clearPendingQuotation();
          return;
        }

        // Use cash tendered/change collected in the checkout dialog if present.
        final dialogAmountTendered =
            checkoutResult['amountTendered'] as double?;
        final dialogChangeGiven = checkoutResult['changeGiven'] as double?;
        _CashCheckoutResult? cashCheckout;
        if (dialogAmountTendered == null || dialogChangeGiven == null) {
          cashCheckout = await _showCashCheckoutDialog(context, total);
          if (!context.mounted || cashCheckout == null) {
            clearPendingQuotation();
            return;
          }
        }

        await _completeSale(
          context,
          ref,
          paymentType: paymentName,
          isCashDrawer: true,
          isCredit: false,
          shiftId: shift?['id'] as String?,
          amountTendered:
              cashCheckout?.amountTendered ?? dialogAmountTendered ?? total,
          changeGiven: cashCheckout?.changeGiven ?? dialogChangeGiven ?? 0.0,
          customerId: customer?['id'] as String?,
          customerName: customer?['name'] as String?,
          convertFromQuotationId: pendingQuotationId,
          loyaltyLedgerId: loyaltyLedgerId,
          loyaltyPoints: loyaltyPoints,
          giftCardId: giftCardId,
          giftCardCode: giftCardCode,
          giftCardAmount: giftCardAmount,
          giftCardBalanceAfter: giftCardBalanceAfter,
        );
      } else {
        await _completeSale(
          context,
          ref,
          paymentType: paymentName,
          isCashDrawer: false,
          isCredit: false,
          customerId: customer?['id'] as String?,
          customerName: customer?['name'] as String?,
          convertFromQuotationId: pendingQuotationId,
          loyaltyLedgerId: loyaltyLedgerId,
          loyaltyPoints: loyaltyPoints,
          giftCardId: giftCardId,
          giftCardCode: giftCardCode,
          giftCardAmount: giftCardAmount,
          giftCardBalanceAfter: giftCardBalanceAfter,
        );
      }
    }
  }

  Future<void> _completeMpesaCheckout(
    BuildContext context,
    WidgetRef ref, {
    required String phoneNumber,
    Map<String, dynamic>? customer,
    String? convertFromQuotationId,
    String? loyaltyLedgerId,
    int? loyaltyPoints,
    String? giftCardId,
    String? giftCardCode,
    double? giftCardAmount,
    double? giftCardBalanceAfter,
  }) async {
    final total = ref.read(cartTotalProvider);
    try {
      _showSnackBar(
        context,
        'Sending M-Pesa STK push...',
        backgroundColor: AppColors.primary,
      );
      final started = await PosPaymentService.startMpesaCheckout(
        amount: total,
        phoneNumber: phoneNumber,
        metadata: {
          'cashierId': SessionService.currentUserId,
          'cashierName': SessionService.currentUserName,
          'source': 'pos',
        },
      );
      if (!context.mounted) return;

      final payment = await _waitForMpesaPayment(context, started.id);
      if (!context.mounted) return;

      if (payment == null || !payment.isPaid) {
        _showSnackBar(
          context,
          payment?.isFailed == true
              ? 'M-Pesa payment failed or was cancelled.'
              : 'M-Pesa payment is still pending. Sale was not saved.',
          backgroundColor: AppColors.warning,
        );
        if (convertFromQuotationId != null) {
          ref.read(activeQuotationIdProvider.notifier).state = null;
        }
        await _refundLoyaltyIfPending(
          ledgerId: loyaltyLedgerId,
          customerId: customer?['id'] as String?,
          points: loyaltyPoints,
        );
        await _refundGiftCardIfPending(
          giftCardId: giftCardId,
          giftCardAmount: giftCardAmount,
        );
        return;
      }

      final confirmed = await showMpesaPaymentConfirmationDialog(
        context,
        payment: payment,
        expectedTotal: total,
        title: 'Confirm M-Pesa Payment',
        confirmLabel: 'Complete Sale',
      );
      if (!context.mounted) return;
      if (!confirmed) {
        _showSnackBar(
          context,
          'M-Pesa payment was confirmed, but the sale was not saved.',
          backgroundColor: AppColors.warning,
        );
        await _refundLoyaltyIfPending(
          ledgerId: loyaltyLedgerId,
          customerId: customer?['id'] as String?,
          points: loyaltyPoints,
        );
        await _refundGiftCardIfPending(
          giftCardId: giftCardId,
          giftCardAmount: giftCardAmount,
        );
        return;
      }

      if (!context.mounted) return;
      final saleId = await _completeSale(
        context,
        ref,
        paymentType: 'M-Pesa',
        isCashDrawer: false,
        isCredit: false,
        customerId: customer?['id'] as String?,
        customerName: customer?['name'] as String?,
        paymentProvider: 'mpesa',
        paymentReference:
            payment.receiptNumber ?? payment.externalReference ?? payment.id,
        paymentStatus: 'paid',
        paymentMetadata: {
          ...payment.metadata,
          'posPaymentId': payment.id,
          'providerSaleLinkStatus': 'pending_reconcile',
        },
        convertFromQuotationId: convertFromQuotationId,
        loyaltyLedgerId: loyaltyLedgerId,
        loyaltyPoints: loyaltyPoints,
        giftCardId: giftCardId,
        giftCardCode: giftCardCode,
        giftCardAmount: giftCardAmount,
        giftCardBalanceAfter: giftCardBalanceAfter,
      );
      if (!context.mounted || saleId == null) return;
      await _linkSavedMpesaPayment(context, payment: payment, saleId: saleId);
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(
          context,
          AppErrorMessage.withContext(
            error,
            prefix: 'M-Pesa checkout failed.',
            fallback: AppErrorMessage.paymentFailed,
          ),
          backgroundColor: AppColors.error,
        );
      }
    }
  }

  Future<void> _completeManualMpesaCheckout(
    BuildContext context,
    WidgetRef ref, {
    required PosPayment payment,
    Map<String, dynamic>? customer,
    String? convertFromQuotationId,
    String? loyaltyLedgerId,
    int? loyaltyPoints,
    String? giftCardId,
    String? giftCardCode,
    double? giftCardAmount,
    double? giftCardBalanceAfter,
  }) async {
    if (!context.mounted) return;
    final saleId = await _completeSale(
      context,
      ref,
      paymentType: 'M-Pesa',
      isCashDrawer: false,
      isCredit: false,
      customerId: customer?['id'] as String?,
      customerName: customer?['name'] as String?,
      paymentProvider: 'mpesa_c2b',
      paymentReference:
          payment.receiptNumber ?? payment.externalReference ?? payment.id,
      paymentStatus: 'paid',
      paymentMetadata: {
        ...payment.metadata,
        'source': 'manual_c2b',
        'posPaymentId': payment.id,
        'providerSaleLinkStatus': 'pending_reconcile',
      },
      convertFromQuotationId: convertFromQuotationId,
      loyaltyLedgerId: loyaltyLedgerId,
      loyaltyPoints: loyaltyPoints,
      giftCardId: giftCardId,
      giftCardCode: giftCardCode,
      giftCardAmount: giftCardAmount,
      giftCardBalanceAfter: giftCardBalanceAfter,
    );
    if (!context.mounted || saleId == null) return;
    await _linkSavedMpesaPayment(context, payment: payment, saleId: saleId);
  }

  Future<void> _linkSavedMpesaPayment(
    BuildContext context, {
    required PosPayment payment,
    required String saleId,
  }) async {
    try {
      await PosPaymentService.linkSale(paymentId: payment.id, saleId: saleId);
      await SaleRepository.updatePaymentLinkStatus(
        saleId: saleId,
        status: 'linked',
      );
    } catch (error) {
      await SaleRepository.updatePaymentLinkStatus(
        saleId: saleId,
        status: 'pending_reconcile',
        error: AppErrorMessage.from(error, fallback: 'Payment link failed'),
      );
      if (!context.mounted) return;
      _showSnackBar(
        context,
        AppErrorMessage.withContext(
          error,
          prefix: 'Sale saved, but M-Pesa link is pending.',
          fallback:
              'Sale saved, but the M-Pesa payment needs reconciliation from payments.',
        ),
        backgroundColor: AppColors.warning,
      );
    }
  }

  Future<PosPayment?> _waitForMpesaPayment(
    BuildContext context,
    String paymentId,
  ) async {
    PosPayment? latest;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Waiting for M-Pesa confirmation...')),
          ],
        ),
      ),
    );
    try {
      for (var attempt = 0; attempt < 30; attempt += 1) {
        await Future.delayed(const Duration(seconds: 3));
        latest = await PosPaymentService.fetchPayment(paymentId);
        if (latest.isPaid || latest.isFailed) {
          return latest;
        }
      }
      return latest;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// Reverses a pending loyalty redemption when the checkout flow ends without
  /// a completed sale (e.g. M-Pesa payment fails or is cancelled).
  Future<void> _refundLoyaltyIfPending({
    required String? ledgerId,
    required String? customerId,
    required int? points,
  }) async {
    if (ledgerId == null ||
        ledgerId.isEmpty ||
        customerId == null ||
        customerId.isEmpty ||
        (points ?? 0) <= 0) {
      return;
    }
    try {
      await LoyaltyRepository.refundRedemption(
        ledgerId: ledgerId,
        customerId: customerId,
        points: points!,
      );
    } catch (_) {
      // best-effort; ledger entry remains for later reconciliation
    }
  }

  /// Reverses a pending gift card redemption when the checkout flow ends
  /// without a completed sale.
  Future<void> _refundGiftCardIfPending({
    required String? giftCardId,
    required double? giftCardAmount,
  }) async {
    if (giftCardId == null ||
        giftCardId.isEmpty ||
        (giftCardAmount ?? 0) <= 0) {
      return;
    }
    try {
      await GiftCardRepository.refundRedemption(
        id: giftCardId,
        amount: giftCardAmount!,
      );
    } catch (_) {
      // best-effort; balance remains for later reconciliation
    }
  }

  Future<String?> _completeSale(
    BuildContext context,
    WidgetRef ref, {
    required String paymentType,
    required bool isCredit,
    bool isCashDrawer = false,
    String? shiftId,
    double? amountTendered,
    double? changeGiven,
    String? customerId,
    String? customerName,
    String? dueDate,
    String? paymentProvider,
    String? paymentReference,
    String? paymentStatus,
    Map<String, dynamic>? paymentMetadata,
    String? convertFromQuotationId,
    String? preAllocatedSaleId,
    String? loyaltyLedgerId,
    int? loyaltyPoints,
    String? giftCardId,
    String? giftCardCode,
    double? giftCardAmount,
    double? giftCardBalanceAfter,
  }) async {
    final cart = ref.read(cartProvider);
    final subtotal = ref.read(cartSubtotalProvider);
    final tax = ref.read(cartTaxProvider);
    final discount = ref.read(discountProvider);
    final total = ref.read(cartTotalProvider);
    final appliedPromotions = ref.read(appliedPromotionsProvider);
    var effectiveGiftCardBalanceAfter = giftCardBalanceAfter;
    int? loyaltyPointsEarned;
    int? loyaltyPointsBalance;
    LoyaltyGiftCardReward? earnedGiftCardReward;

    final saleItems = cart
        .map(
          (item) => {
            'line_type': item.lineType,
            'product_id': item.productId,
            'product_name': _cartItemDisplayName(item),
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'unit': item.unit,
          },
        )
        .toList();

    final salePaymentMetadata = <String, dynamic>{
      if (paymentMetadata != null) ...paymentMetadata,
      if ((loyaltyLedgerId ?? '').isNotEmpty)
        'loyaltyLedgerId': loyaltyLedgerId,
      if ((loyaltyPoints ?? 0) > 0) 'loyaltyPointsRedeemed': loyaltyPoints,
      if ((giftCardId ?? '').isNotEmpty) 'giftCardId': giftCardId,
      if ((giftCardCode ?? '').isNotEmpty) 'giftCardCode': giftCardCode,
      if ((giftCardAmount ?? 0) > 0) 'giftCardAmount': giftCardAmount,
      ...?switch (effectiveGiftCardBalanceAfter) {
        final balanceAfter? => {'giftCardBalanceAfter': balanceAfter},
        null => null,
      },
      if (appliedPromotions.isNotEmpty) 'promotions': appliedPromotions,
    };

    final String saleId;
    try {
      saleId = await SaleRepository.createSale(
        saleId: preAllocatedSaleId,
        totalAmount: total,
        tax: tax,
        discount: discount,
        paymentType: paymentType,
        isCashDrawer: isCashDrawer,
        userId: SessionService.currentUserId.isNotEmpty
            ? SessionService.currentUserId
            : 'admin',
        shiftId: shiftId,
        items: cart.map((item) => item.toSaleItem()).toList(),
        amountTendered: amountTendered,
        changeGiven: changeGiven,
        customerId: customerId,
        customerName: customerName,
        dueDate: dueDate,
        paymentProvider: paymentProvider,
        paymentReference: paymentReference,
        paymentStatus: paymentStatus,
        paymentMetadata: salePaymentMetadata.isEmpty
            ? null
            : salePaymentMetadata,
      );
    } catch (e) {
      ref.read(activeQuotationIdProvider.notifier).state = null;
      if (loyaltyLedgerId != null &&
          loyaltyLedgerId.isNotEmpty &&
          customerId != null &&
          customerId.isNotEmpty) {
        try {
          await LoyaltyRepository.refundRedemption(
            ledgerId: loyaltyLedgerId,
            customerId: customerId,
            points: loyaltyPoints ?? 0,
          );
        } catch (_) {
          // best-effort; ledger entry remains for later reconciliation
        }
      }
      if (giftCardId != null &&
          giftCardId.isNotEmpty &&
          (giftCardAmount ?? 0) > 0) {
        try {
          await GiftCardRepository.refundRedemption(
            id: giftCardId,
            amount: giftCardAmount!,
          );
        } catch (_) {
          // best-effort; balance remains for later reconciliation
        }
      }
      if (context.mounted) {
        _showSnackBar(
          context,
          AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          backgroundColor: AppColors.error,
        );
      }
      return null;
    }

    _clearCurrentSale(ref);
    ref.invalidate(filteredProductsProvider);
    ref.invalidate(posTodayStatsProvider);
    ref.invalidate(posRecentSalesProvider);
    invalidateShiftProviders(ref);

    // ── Mark any linked service orders as paid ─────────────────────────
    final serviceOrderIds = cart
        .where(
          (item) =>
              item.serviceOrderId != null && item.serviceOrderId!.isNotEmpty,
        )
        .map((item) => item.serviceOrderId!)
        .toSet();
    if (serviceOrderIds.isNotEmpty) {
      try {
        for (final orderId in serviceOrderIds) {
          await ServiceRepository.attachSaleToOrder(orderId, saleId);
        }
      } catch (error) {
        if (context.mounted) {
          _showSnackBar(
            context,
            AppErrorMessage.withContext(
              error,
              prefix: 'Sale saved, but service order was not updated.',
              fallback: 'Sale saved, but service order was not updated.',
            ),
            backgroundColor: AppColors.warning,
          );
        }
      } finally {
        ref.invalidate(serviceOrdersProvider);
      }
    }
    EtimsSubmissionResult? etimsResult;
    try {
      etimsResult = await EtimsService.submitSaleIfEnabled(saleId);
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(
          context,
          AppErrorMessage.withContext(
            error,
            prefix: 'Sale saved, but eTIMS was not submitted.',
            fallback: 'Sale saved, but eTIMS was not submitted.',
          ),
          backgroundColor: AppColors.warning,
        );
      }
    }
    // ──────────────────────────────────────────────────────────────────

    // ── Mark linked quotation as converted (only after successful payment)
    if (convertFromQuotationId != null && convertFromQuotationId.isNotEmpty) {
      try {
        await QuotationRepository.markConverted(
          convertFromQuotationId,
          saleId: saleId,
        );
        ref.read(lastSavedQuotationProvider.notifier).state = null;
        bumpQuotationsList(ref);
      } catch (error) {
        // Don't fail the sale; surface a warning so admin can fix manually.
        if (context.mounted) {
          _showSnackBar(
            context,
            AppErrorMessage.withContext(
              error,
              prefix: 'Sale saved, but quotation status was not updated.',
              fallback: 'Sale saved, but quotation status was not updated.',
            ),
            backgroundColor: AppColors.warning,
          );
        }
      } finally {
        ref.read(activeQuotationIdProvider.notifier).state = null;
      }
    }
    // ──────────────────────────────────────────────────────────────────

    // ── Loyalty: link a pending redemption and award earn points ────────
    if (customerId != null && customerId.isNotEmpty) {
      try {
        if (loyaltyLedgerId != null && loyaltyLedgerId.isNotEmpty) {
          await LoyaltyRepository.linkRedemptionToSale(
            ledgerId: loyaltyLedgerId,
            saleId: saleId,
          );
        }
        final earned = await LoyaltyRepository.earnPointsForSale(
          customerId: customerId,
          saleId: saleId,
          saleTotal: total,
        );
        earnedGiftCardReward =
            await LoyaltyRepository.issueGiftCardRewardIfEligible(
              customerId: customerId,
              saleId: saleId,
            );
        final currentPoints = await LoyaltyRepository.getCustomerPoints(
          customerId,
        );
        if (earned > 0 || (loyaltyPoints ?? 0) > 0 || currentPoints > 0) {
          loyaltyPointsEarned = earned;
          loyaltyPointsBalance = currentPoints;
        }
        if (earned > 0 && context.mounted) {
          _showSnackBar(
            context,
            '$earned loyalty point${earned == 1 ? '' : 's'} earned.',
            backgroundColor: AppColors.success,
          );
        }
        final earnedReward = earnedGiftCardReward;
        if (earnedReward != null && context.mounted) {
          _showSnackBar(
            context,
            'Gift card ${earnedReward.code} earned: ${GiftCardRepository.formatBalance(earnedReward.amount)}',
            backgroundColor: AppColors.success,
          );
        }
        if (earnedReward != null) {
          unawaited(
            _sendEarnedGiftCardApiIfAvailable(
              customerId: customerId,
              reward: earnedReward,
            ),
          );
        }
      } catch (error) {
        if (context.mounted) {
          _showSnackBar(
            context,
            AppErrorMessage.withContext(
              error,
              prefix: 'Sale saved, but loyalty was not updated.',
              fallback: 'Sale saved, but loyalty was not updated.',
            ),
            backgroundColor: AppColors.warning,
          );
        }
      }
    }
    // ── Gift card: confirm redemption applied to this sale ───────────────
    if (giftCardId != null &&
        giftCardId.isNotEmpty &&
        (giftCardAmount ?? 0) > 0) {
      try {
        await GiftCardRepository.linkLatestRedemptionToSale(
          giftCardId: giftCardId,
          saleId: saleId,
        );
        final updatedGiftCard = await GiftCardRepository.getById(giftCardId);
        effectiveGiftCardBalanceAfter =
            (updatedGiftCard?['balance'] as num?)?.toDouble() ??
            effectiveGiftCardBalanceAfter;
      } catch (_) {
        // Best-effort: checkout already carries the latest balance snapshot.
      }
      if (context.mounted) {
        final redeemedAmount = giftCardAmount ?? 0;
        final balanceAfter = effectiveGiftCardBalanceAfter;
        final balanceText = balanceAfter == null
            ? ''
            : ' - balance ${GiftCardRepository.formatBalance(balanceAfter)}';
        _showSnackBar(
          context,
          'Gift card ${giftCardCode ?? ''} redeemed: ${GiftCardRepository.formatBalance(redeemedAmount)}$balanceText',
          backgroundColor: AppColors.success,
        );
      }
    }
    // ──────────────────────────────────────────────────────────────────

    final balanceMetadata = <String, dynamic>{
      ...?switch (loyaltyPointsEarned) {
        final pointsEarned? => {'loyaltyPointsEarned': pointsEarned},
        null => null,
      },
      ...?switch (loyaltyPointsBalance) {
        final pointsBalance? => {'loyaltyPointsBalance': pointsBalance},
        null => null,
      },
      if (earnedGiftCardReward case final reward?) ...reward.toMetadata(),
      ...?switch (effectiveGiftCardBalanceAfter) {
        final balanceAfter? => {'giftCardBalanceAfter': balanceAfter},
        null => null,
      },
    };
    if (balanceMetadata.isNotEmpty) {
      try {
        await SaleRepository.mergePaymentMetadata(
          saleId: saleId,
          metadata: balanceMetadata,
        );
      } catch (_) {
        // Best-effort: receipt still receives the in-memory balance values.
      }
    }

    if (context.mounted) {
      await _openCashDrawerAfterSale(context, isCashDrawer);
    }

    if (context.mounted) {
      _showSaleSuccessDialog(
        context,
        saleId: saleId,
        total: total,
        subtotal: subtotal,
        tax: tax,
        discount: discount,
        saleItems: saleItems,
        paymentType: paymentType,
        customerName: customerName,
        amountTendered: amountTendered ?? 0,
        changeGiven: changeGiven ?? 0,
        balanceDue: isCredit ? total : 0,
        dueDate: dueDate,
        cashierName: SessionService.currentUserName,
        etimsResult: etimsResult,
        loyaltyPointsRedeemed: loyaltyPoints,
        loyaltyPointsEarned: loyaltyPointsEarned,
        loyaltyPointsBalance: loyaltyPointsBalance,
        earnedGiftCardReward: earnedGiftCardReward,
        customerId: customerId,
        giftCardCode: giftCardCode,
        giftCardRedeemed: giftCardAmount,
        giftCardBalance: effectiveGiftCardBalanceAfter,
      );
    }
    return saleId;
  }

  Future<void> _openCashDrawerAfterSale(
    BuildContext context,
    bool isCashDrawer,
  ) async {
    if (!isCashDrawer || !CashDrawerService.isReady) {
      return;
    }

    try {
      final result = await CashDrawerService.openAfterCashSale();
      if (!context.mounted || result.success) {
        return;
      }

      _showSnackBar(
        context,
        result.message,
        backgroundColor: AppColors.warning,
      );
    } catch (error) {
      if (!context.mounted) return;
      _showSnackBar(
        context,
        AppErrorMessage.withContext(
          error,
          prefix: 'Sale saved, but cash drawer did not open.',
          fallback: 'Sale saved, but cash drawer did not open.',
        ),
        backgroundColor: AppColors.warning,
      );
    }
  }

  void _showSaleSuccessDialog(
    BuildContext context, {
    required String saleId,
    required double total,
    required double subtotal,
    required double tax,
    required double discount,
    required List<Map<String, dynamic>> saleItems,
    required String paymentType,
    String? customerName,
    double amountTendered = 0,
    double changeGiven = 0,
    double balanceDue = 0,
    String? dueDate,
    required String cashierName,
    EtimsSubmissionResult? etimsResult,
    int? loyaltyPointsRedeemed,
    int? loyaltyPointsEarned,
    int? loyaltyPointsBalance,
    LoyaltyGiftCardReward? earnedGiftCardReward,
    String? customerId,
    String? giftCardCode,
    double? giftCardRedeemed,
    double? giftCardBalance,
  }) {
    final isKopesha = paymentType.toLowerCase() == 'kopesha';
    final hasAmountTendered = amountTendered > 0;
    final hasLoyaltySummary =
        (loyaltyPointsRedeemed ?? 0) > 0 ||
        (loyaltyPointsEarned ?? 0) > 0 ||
        loyaltyPointsBalance != null;
    final hasGiftCardSummary =
        (giftCardRedeemed ?? 0) > 0 || giftCardBalance != null;
    final hasEarnedGiftCardSummary = earnedGiftCardReward != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isKopesha
                  ? Icons.account_balance_wallet_outlined
                  : Icons.check_circle,
              color: isKopesha ? AppColors.warning : AppColors.success,
              size: 32,
            ),
            SizedBox(width: 12),
            Text(isKopesha ? 'Kopesha Saved' : 'Sale Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isKopesha ? AppColors.warning : AppColors.success,
              ),
            ),
            if (hasAmountTendered) ...[
              SizedBox(height: 12),
              Text(
                'Received: ${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                'Change Returned: ${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: changeGiven > 0
                      ? AppColors.primaryLight
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: 8),
            Text(
              'Sale ID: ${saleId.substring(0, 8)}...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            if (etimsResult != null) ...[
              SizedBox(height: 8),
              Text(
                etimsResult.status == 'submitted'
                    ? 'KRA eTIMS submitted: ${etimsResult.controlUnitInvoiceNumber ?? etimsResult.invoiceNumber ?? 'received'}'
                    : 'KRA eTIMS: ${etimsResult.status.replaceAll('_', ' ')}',
                style: TextStyle(
                  color: etimsResult.status == 'submitted'
                      ? AppColors.success
                      : AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((etimsResult.errorMessage ?? '').isNotEmpty)
                Text(
                  etimsResult.errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
            if (customerName != null) ...[
              SizedBox(height: 8),
              Text(
                'Customer: $customerName',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (balanceDue > 0) ...[
              SizedBox(height: 8),
              Text(
                'Outstanding Kopesha: ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                style: TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (dueDate != null) ...[
              SizedBox(height: 8),
              Text(
                'Due date: $dueDate',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasLoyaltySummary) ...[
              SizedBox(height: 8),
              Text(
                [
                  if ((loyaltyPointsRedeemed ?? 0) > 0)
                    'redeemed $loyaltyPointsRedeemed pts',
                  if ((loyaltyPointsEarned ?? 0) > 0)
                    'earned $loyaltyPointsEarned pts',
                  if (loyaltyPointsBalance != null)
                    'balance $loyaltyPointsBalance pts',
                ].join(' - '),
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (hasGiftCardSummary) ...[
              SizedBox(height: 8),
              Text(
                [
                  if ((giftCardCode ?? '').trim().isNotEmpty)
                    'Gift card $giftCardCode',
                  if ((giftCardRedeemed ?? 0) > 0)
                    'used ${GiftCardRepository.formatBalance(giftCardRedeemed!)}',
                  if (giftCardBalance != null)
                    'balance ${GiftCardRepository.formatBalance(giftCardBalance)}',
                ].join(' - '),
                style: TextStyle(
                  color: AppColors.fuchsia,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (hasEarnedGiftCardSummary) ...[
              SizedBox(height: 8),
              Text(
                'Earned gift card ${earnedGiftCardReward.code} - ${GiftCardRepository.formatBalance(earnedGiftCardReward.amount)}',
                style: TextStyle(
                  color: AppColors.fuchsia,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                [
                  '${earnedGiftCardReward.pointsSpent} pts converted',
                  'balance ${earnedGiftCardReward.pointsBalance} pts',
                  if ((earnedGiftCardReward.expiresAt ?? '').trim().isNotEmpty)
                    'expires ${earnedGiftCardReward.expiresAt}',
                ].join(' - '),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Done')),
          if (earnedGiftCardReward != null &&
              customerId != null &&
              customerId.trim().isNotEmpty)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(
                  _showEarnedGiftCardMessage(
                    context,
                    customerId: customerId,
                    reward: earnedGiftCardReward,
                  ),
                );
              },
              icon: Icon(Icons.send_outlined, size: 18),
              label: Text(
                MessagingService.allowApiSend ? 'Send Again' : 'Send Gift Card',
              ),
            ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ReceiptService.showReceiptPreview(
                context,
                saleId: saleId,
                total: total,
                subtotal: subtotal,
                tax: tax,
                discount: discount,
                paymentType: paymentType,
                items: saleItems,
                customerName: customerName,
                amountTendered: amountTendered,
                changeGiven: changeGiven,
                balanceDue: balanceDue,
                dueDate: dueDate,
                cashierName: cashierName,
                documentDate: DateTime.now().toIso8601String(),
                etimsStatus: etimsResult?.status,
                etimsInvoiceNumber: etimsResult?.invoiceNumber,
                etimsControlUnitInvoiceNumber:
                    etimsResult?.controlUnitInvoiceNumber,
                etimsControlUnitSerial: etimsResult?.controlUnitSerial,
                etimsVerificationUrl: etimsResult?.verificationUrl,
                etimsQrCode: etimsResult?.qrCode,
                showTenderedBreakdown: hasAmountTendered,
                loyaltyPointsRedeemed: loyaltyPointsRedeemed,
                loyaltyPointsEarned: loyaltyPointsEarned,
                loyaltyPointsBalance: loyaltyPointsBalance,
                giftCardCode: giftCardCode,
                giftCardRedeemed: giftCardRedeemed,
                giftCardBalance: giftCardBalance,
                earnedGiftCardCode: earnedGiftCardReward?.code,
                earnedGiftCardAmount: earnedGiftCardReward?.amount,
                earnedGiftCardExpiresAt: earnedGiftCardReward?.expiresAt,
              );
            },
            icon: Icon(Icons.receipt_long, size: 18),
            label: Text('Print Receipt'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEarnedGiftCardMessage(
    BuildContext context, {
    required String customerId,
    required LoyaltyGiftCardReward reward,
  }) async {
    final customer = await CustomerRepository.getById(customerId);
    if (!context.mounted) return;
    if (customer == null) {
      _showSnackBar(
        context,
        'Customer was not found.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    final customerName = customer['name']?.toString() ?? 'Customer';
    final phone = customer['phone']?.toString() ?? '';
    final email = customer['email']?.toString() ?? '';
    if (phone.trim().isEmpty && email.trim().isEmpty) {
      _showSnackBar(
        context,
        'Add a phone or email for $customerName before sending.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    await CustomerMessageDialog.show(
      context,
      customerName: customerName,
      phoneNumber: phone,
      emailAddress: email,
      initialMessage: MessagingService.giftCardRewardMessage(
        customerName: customerName,
        code: reward.code,
        amount: GiftCardRepository.formatBalance(reward.amount),
        expiresAt: reward.expiresAt,
        pointsSpent: reward.pointsSpent,
      ),
      metadata: {
        'source': 'loyalty_gift_card_reward',
        'giftCardId': reward.giftCardId,
        'giftCardCode': reward.code,
        'giftCardAmount': reward.amount,
        'customerId': customerId,
      },
    );
  }

  Future<void> _sendEarnedGiftCardApiIfAvailable({
    required String customerId,
    required LoyaltyGiftCardReward reward,
  }) async {
    if (!MessagingService.allowApiSend) {
      return;
    }
    try {
      final customer = await CustomerRepository.getById(customerId);
      final customerName = customer?['name']?.toString() ?? 'Customer';
      final phone = customer?['phone']?.toString() ?? '';
      if (phone.trim().isEmpty) {
        return;
      }
      await MessagingService.sendApi(
        channel: CustomerMessageChannel.whatsapp,
        phoneNumber: phone,
        message: MessagingService.giftCardRewardMessage(
          customerName: customerName,
          code: reward.code,
          amount: GiftCardRepository.formatBalance(reward.amount),
          expiresAt: reward.expiresAt,
          pointsSpent: reward.pointsSpent,
        ),
        metadata: {
          'source': 'loyalty_gift_card_reward_auto',
          'giftCardId': reward.giftCardId,
          'giftCardCode': reward.code,
          'giftCardAmount': reward.amount,
          'customerId': customerId,
        },
      );
    } catch (_) {
      // Best-effort notification. The receipt and manual send action still
      // carry the gift card code.
    }
  }

  Future<_CashCheckoutResult?> _showCashCheckoutDialog(
    BuildContext context,
    double total,
  ) async {
    final controller = TextEditingController(text: total.toStringAsFixed(2));
    var tenderedAmount = total;
    String? errorText;

    final result = await showDialog<_CashCheckoutResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.of(context);
          final isCompact = media.size.width < 560;
          final hasEnoughCash = tenderedAmount + 0.001 >= total;
          final changeGiven = hasEnoughCash ? tenderedAmount - total : 0.0;

          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 40,
              vertical: isCompact ? 12 : 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: EdgeInsets.fromLTRB(
              isCompact ? 16 : 24,
              isCompact ? 16 : 24,
              isCompact ? 16 : 24,
              0,
            ),
            contentPadding: EdgeInsets.all(isCompact ? 16 : 24),
            actionsPadding: EdgeInsets.fromLTRB(
              isCompact ? 16 : 24,
              0,
              isCompact ? 16 : 24,
              isCompact ? 16 : 24,
            ),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 8,
            title: Row(
              children: [
                Icon(Icons.payments_outlined, color: AppColors.success),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cash Checkout',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height * (isCompact ? 0.6 : 0.65),
              ),
              child: SizedBox(
                width: isCompact ? media.size.width - 56 : 420,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Due',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isCompact ? 24 : 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Cash Received',
                          prefixText: ShopSettings.currency,
                          errorText: errorText,
                          helperText: hasEnoughCash
                              ? 'Change to return: ${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}'
                              : 'Enter at least ${ShopSettings.currency}${total.toStringAsFixed(2)}',
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            tenderedAmount =
                                double.tryParse(value.trim()) ?? 0.0;
                            errorText = null;
                          });
                        },
                      ),
                      SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            controller.text = total.toStringAsFixed(2);
                            setDialogState(() {
                              tenderedAmount = total;
                              errorText = null;
                            });
                          },
                          icon: Icon(Icons.restart_alt),
                          label: Text('Use Exact Amount'),
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: hasEnoughCash
                              ? AppColors.primaryLight.withValues(alpha: 0.08)
                              : AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasEnoughCash
                                  ? Icons.reply_outlined
                                  : Icons.warning_amber_rounded,
                              color: hasEnoughCash
                                  ? AppColors.primaryLight
                                  : AppColors.warning,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hasEnoughCash
                                        ? 'Change Returned'
                                        : 'More Cash Needed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: hasEnoughCash
                                          ? AppColors.primaryLight
                                          : AppColors.warning,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '${ShopSettings.currency}${(hasEnoughCash ? changeGiven : total - tenderedAmount).toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: isCompact ? double.infinity : null,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel'),
                ),
              ),
              SizedBox(
                width: isCompact ? double.infinity : null,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final parsed = double.tryParse(controller.text.trim());
                    if (parsed == null) {
                      setDialogState(() {
                        errorText = 'Enter a valid cash amount';
                      });
                      return;
                    }
                    if (parsed + 0.001 < total) {
                      setDialogState(() {
                        errorText = 'Cash received must cover the sale total';
                      });
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      _CashCheckoutResult(
                        amountTendered: parsed,
                        changeGiven: parsed - total,
                      ),
                    );
                  },
                  icon: Icon(Icons.check_circle_outline),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  label: Text(
                    'Complete Sale',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    return result;
  }

  String _defaultHoldName(List<CartItem> cart) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (cart.isEmpty) {
      return 'Held Sale $time';
    }
    if (cart.length == 1) {
      return '${cart.first.productName} $time';
    }
    return '${cart.first.productName} +${cart.length - 1} $time';
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    required Color backgroundColor,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
      ),
    );
  }

  double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

// ──────────────── QUOTATION CART SIDE ────────────────

class _QuotationCartSide extends ConsumerStatefulWidget {
  @override
  ConsumerState<_QuotationCartSide> createState() => _QuotationCartSideState();
}

class _QuotationCartSideState extends ConsumerState<_QuotationCartSide> {
  final _notesController = TextEditingController();
  final _customerSearchController = TextEditingController();
  bool _isSaving = false;
  bool _isConverting = false;

  @override
  void dispose() {
    _notesController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final current = ref.read(quotationExpiryProvider);
    DateTime initial = now.add(const Duration(days: 7));
    if (current != null && current.isNotEmpty) {
      final parsed = DateTime.tryParse(current);
      if (parsed != null) initial = parsed;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      final iso =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      ref.read(quotationExpiryProvider.notifier).state = iso;
    }
  }

  Future<void> _saveQuotation() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack(
        'Add at least one product before saving a quotation.',
        color: AppColors.warning,
      );
      return;
    }
    final customer = ref.read(quotationCustomerProvider);
    if (customer == null) {
      _showSnack(
        'Please select a customer for this quotation.',
        color: AppColors.warning,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final subtotal = ref.read(cartSubtotalProvider);
      final tax = ref.read(cartTaxProvider);
      final discount = ref.read(discountProvider);
      final total = ref.read(cartTotalProvider);
      final expiry = ref.read(quotationExpiryProvider);
      final notes = _notesController.text.trim();

      final quotationId = await QuotationRepository.createQuotation(
        customerId: customer['id'] as String? ?? '',
        customerName: customer['name'] as String? ?? '',
        subtotal: subtotal,
        discountTotal: discount,
        taxTotal: tax,
        total: total,
        userId: SessionService.currentUserId.isNotEmpty
            ? SessionService.currentUserId
            : 'admin',
        items: cart.map((item) => item.toQuotationItem()).toList(),
        expiryDate: expiry,
        notes: notes.isEmpty ? null : notes,
        status: 'draft',
      );

      final saved = {
        'id': quotationId,
        'quotation_no': 'QUO-pending',
        'customer_name': customer['name'],
        'total': total,
        'subtotal': subtotal,
        'tax': tax,
        'discount': discount,
        'expiry_date': expiry,
        'notes': notes.isEmpty ? null : notes,
        'items': cart.map((item) => item.toQuotationItem()).toList(),
      };
      // Refresh the real record (with the generated quotation_no).
      final fresh = await QuotationRepository.getWithItems(quotationId);
      if (fresh != null) {
        saved['quotation_no'] = fresh['quotation_no'];
      }
      ref.read(lastSavedQuotationProvider.notifier).state = saved;
      bumpQuotationsList(ref);
      _showSnack(
        'Quotation ${saved['quotation_no']} saved.',
        color: AppColors.success,
      );
    } catch (e) {
      _showSnack(
        AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
        color: AppColors.error,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _printQuotation(Map<String, dynamic> quotation) async {
    if (!mounted) return;
    final items = (quotation['items'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await ReceiptService.showReceiptPreview(
      context,
      saleId: quotation['id'] as String,
      total: (quotation['total'] as num).toDouble(),
      subtotal: (quotation['subtotal'] as num).toDouble(),
      tax: (quotation['tax'] as num).toDouble(),
      discount: (quotation['discount'] as num).toDouble(),
      paymentType: 'N/A',
      items: items,
      customerName: quotation['customer_name'] as String?,
      dueDate: quotation['expiry_date'] as String?,
      note: quotation['notes'] as String?,
      documentTitle: 'Quotation',
      recordLabel: 'Quote',
      previewTitle: 'Quotation Preview',
      fileNamePrefix: 'quotation',
      isQuotation: true,
      quotationNo: quotation['quotation_no'] as String?,
      quotationStatus: 'DRAFT',
    );
  }

  Future<void> _convertToSale(Map<String, dynamic> quotation) async {
    final quotationId = quotation['id'] as String;
    setState(() => _isConverting = true);
    try {
      final loaded = await QuotationRepository.loadForConvert(quotationId);
      if (!mounted) return;
      if (loaded.items.isEmpty) {
        _showSnack(
          loaded.adjustments.isEmpty
              ? 'This quotation has no items available to convert.'
              : 'No items available. ${loaded.adjustments.first}',
          color: AppColors.warning,
        );
        return;
      }

      final proceed = loaded.adjustments.isEmpty
          ? true
          : await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Stock changed since quoting'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Some quotation items were adjusted to match '
                          'current stock:',
                        ),
                        SizedBox(height: 10),
                        ...loaded.adjustments.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 16,
                                  color: AppColors.warning,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    a,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Continue converting to a sale?',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Convert'),
                      ),
                    ],
                  ),
                ) ??
                false;
      if (!proceed) return;

      ref.read(cartProvider.notifier).restoreQuotationItems(loaded.items);
      ref.read(discountProvider.notifier).state =
          (quotation['discount'] as num?)?.toDouble() ?? 0.0;
      ref.read(activeQuotationIdProvider.notifier).state = quotationId;
      ref.read(posModeProvider.notifier).state = PosMode.sale;
      _showSnack(
        'Quotation loaded into Sale tab. Take payment to complete.',
        color: AppColors.primaryLight,
      );
    } catch (e) {
      _showSnack(
        AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
        color: AppColors.error,
      );
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  void _clearQuotationForm() {
    ref.read(cartProvider.notifier).clear();
    ref.read(discountProvider.notifier).state = 0.0;
    ref.read(quotationCustomerProvider.notifier).state = null;
    ref.read(quotationExpiryProvider.notifier).state = null;
    _notesController.clear();
    ref.read(lastSavedQuotationProvider.notifier).state = null;
  }

  void _showSnack(String message, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final tax = ref.watch(cartTaxProvider);
    final discount = ref.watch(discountProvider);
    final total = ref.watch(cartTotalProvider);
    final customer = ref.watch(quotationCustomerProvider);
    final expiry = ref.watch(quotationExpiryProvider);
    final savedQuotation = ref.watch(lastSavedQuotationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobileCart =
        MediaQuery.sizeOf(context).width <= 430 ||
        MediaQuery.sizeOf(context).width <= 430;

    return Container(
      color: isDark
          ? AppColors.darkSurface
          : Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Quotation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearQuotationForm,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.error,
                    ),
                    label: Text(
                      'Clear',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.request_quote_outlined,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Add products to build a quotation',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.all(isMobileCart ? 12 : 16),
                    children: [
                      ...cart.map(
                        (item) => _CartItemRow(
                          item: item,
                          showProfit: SessionService.canAccessFeature(
                            UserAccessProfile.featureProfitLoss,
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Summary
                      _SummaryRow(
                        title: 'Subtotal',
                        value:
                            '${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
                      ),
                      SizedBox(height: 8),
                      _SummaryRow(
                        title: 'Tax (${ShopSettings.taxRate}%)',
                        value:
                            '${ShopSettings.currency}${tax.toStringAsFixed(2)}',
                      ),
                      if (discount > 0) ...[
                        SizedBox(height: 8),
                        _SummaryRow(
                          title: 'Discount',
                          value:
                              '-${ShopSettings.currency}${discount.toStringAsFixed(2)}',
                          isDiscount: true,
                        ),
                      ],
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _CartSide._showDiscountDialog(
                                context,
                                ref,
                                subtotal,
                              ),
                              icon: Icon(Icons.local_offer_outlined, size: 18),
                              label: Text(
                                discount > 0 ? 'Edit Discount' : 'Add Discount',
                              ),
                            ),
                          ),
                          if (discount > 0) ...[
                            SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Clear discount',
                              onPressed: () =>
                                  ref.read(discountProvider.notifier).state = 0,
                              icon: Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 16),
                      Divider(),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Flexible(
                            child: Text(
                              '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      // Customer selector
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Customer',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 8),
                      if (customer != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person, color: AppColors.primaryLight),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer['name'] as String? ?? 'Customer',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if ((customer['phone'] as String?)
                                            ?.isNotEmpty ==
                                        true)
                                      Text(
                                        customer['phone'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    ref
                                            .read(
                                              quotationCustomerProvider
                                                  .notifier,
                                            )
                                            .state =
                                        null,
                                tooltip: 'Clear customer',
                              ),
                            ],
                          ),
                        )
                      else
                        _QuotationCustomerPicker(),
                      SizedBox(height: 16),
                      // Expiry date
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Expiry date (optional)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickExpiryDate,
                        icon: Icon(Icons.event_outlined, size: 18),
                        label: Text(
                          expiry != null && expiry.isNotEmpty
                              ? 'Valid until: ${_formatDate(expiry)}'
                              : 'Set expiry date',
                        ),
                      ),
                      SizedBox(height: 16),
                      // Notes
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Notes (optional)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 8),
                      TextField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Add a note for the customer...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      // Actions
                      if (savedQuotation == null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _saveQuotation,
                            icon: _isSaving
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(Icons.save_outlined),
                            label: Text('Save Quotation'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppColors.primary,
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Saved: ${savedQuotation['quotation_no']}',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _printQuotation(savedQuotation),
                                icon: Icon(Icons.print_outlined, size: 18),
                                label: Text('Print'),
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isConverting
                                    ? null
                                    : () => _convertToSale(savedQuotation),
                                icon: _isConverting
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(Icons.swap_horiz, size: 18),
                                label: Text('Convert to Sale'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: _clearQuotationForm,
                            icon: Icon(Icons.add, size: 18),
                            label: Text('New Quotation'),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuotationCustomerPicker extends ConsumerStatefulWidget {
  @override
  ConsumerState<_QuotationCustomerPicker> createState() =>
      _QuotationCustomerPickerState();
}

class _QuotationCustomerPickerState
    extends ConsumerState<_QuotationCustomerPicker> {
  final _controller = TextEditingController();
  bool _showResults = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          onTap: () => setState(() => _showResults = true),
          onChanged: (value) {
            ref.read(_quotationCustomerQueryProvider.notifier).state = value;
            setState(() => _showResults = true);
          },
          decoration: InputDecoration(
            hintText: 'Search customer by name or phone',
            prefixIcon: Icon(
              Icons.search,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _controller.clear();
                      ref.read(_quotationCustomerQueryProvider.notifier).state =
                          '';
                    },
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_showResults)
          Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(quotationCustomerSearchProvider);
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 220),
                child: async.when(
                  data: (customers) {
                    if (customers.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'No customers found',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: customers.length,
                      separatorBuilder: (_, _) => Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = customers[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.person_outline, size: 20),
                          title: Text(
                            c['name'] as String? ?? 'Customer',
                            style: TextStyle(fontSize: 13),
                          ),
                          subtitle: (c['phone'] as String?)?.isNotEmpty == true
                              ? Text(
                                  c['phone'] as String,
                                  style: TextStyle(fontSize: 11),
                                )
                              : null,
                          onTap: () {
                            ref.read(quotationCustomerProvider.notifier).state =
                                c;
                            setState(() => _showResults = false);
                            _controller.clear();
                            ref
                                    .read(
                                      _quotationCustomerQueryProvider.notifier,
                                    )
                                    .state =
                                '';
                          },
                        );
                      },
                    );
                  },
                  loading: () => Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Search failed',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _CashCheckoutResult {
  final double amountTendered;
  final double changeGiven;

  const _CashCheckoutResult({
    required this.amountTendered,
    required this.changeGiven,
  });
}

// ──────────────── Reusable Widgets ────────────────

class _HeldSaleCard extends StatelessWidget {
  final Map<String, dynamic> hold;
  final Future<void> Function() onResume;
  final Future<void> Function() onDiscard;

  const _HeldSaleCard({
    required this.hold,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final name = hold['name'] as String? ?? 'Held Sale';
    final itemCount = _asInt(hold['item_count']);
    final total = _asDouble(hold['total']);
    final updatedAt = hold['updated_at'] as String?;
    final cashierName = hold['cashier_name'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeldSaleMetaChip(
                          icon: Icons.shopping_bag_outlined,
                          label: '$itemCount item${itemCount == 1 ? '' : 's'}',
                        ),
                        _HeldSaleMetaChip(
                          icon: Icons.schedule_outlined,
                          label: _formatHeldTimestamp(updatedAt),
                        ),
                        if (cashierName != null &&
                            cashierName.trim().isNotEmpty)
                          _HeldSaleMetaChip(
                            icon: Icons.person_outline,
                            label: cashierName.trim(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Text(
                '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onResume,
                  icon: Icon(Icons.playlist_add_check_circle_outlined),
                  label: Text('Resume'),
                ),
              ),
              SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onDiscard,
                icon: Icon(Icons.delete_outline, color: AppColors.error),
                label: Text(
                  'Discard',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

class _HeldSaleMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeldSaleMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatHeldTimestamp(String? rawValue) {
  final parsed = rawValue == null ? null : DateTime.tryParse(rawValue);
  if (parsed == null) {
    return 'Saved earlier';
  }

  final local = parsed.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day $month, $hour:$minute';
}

String _cartItemDisplayName(CartItem item) {
  final parts = <String>[item.productName];
  final variantName = item.variantName?.trim() ?? '';
  if (variantName.isNotEmpty) {
    parts.add(variantName);
  }
  final colorName = item.variantColorName?.trim() ?? '';
  if (colorName.isNotEmpty) {
    parts.add(colorName);
  }
  return parts.join(' - ');
}

class _CartItemRow extends ConsumerWidget {
  final CartItem item;
  final bool showProfit;

  const _CartItemRow({required this.item, required this.showProfit});

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    if (item.isService) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service charges stay at one job per line item.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final controller = TextEditingController(
      text: UnitUtils.formatQuantity(item.quantity),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set Quantity (${UnitUtils.label(item.unit)})'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity',
            helperText: item.usesConversion
                ? 'Available: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)})'
                : 'Available: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value == null ||
                  !ref
                      .read(cartProvider.notifier)
                      .setQuantity(item.cartKey, value)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      item.usesConversion
                          ? 'Enter a quantity up to ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)} available).'
                          : 'Enter a quantity up to ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final itemName = _cartItemDisplayName(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          itemName,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 2),
        Text(
          item.isService
              ? '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} service charge'
              : '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} ${UnitUtils.priceLabel(item.unit)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 2),
        if (!item.isService && item.tracksStock)
          Text(
            item.usesConversion
                ? 'In stock: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)})'
                : 'In stock: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else if (!item.isService)
          Text(
            'No stock limit',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          )
        else
          Text(
            item.serviceOrderId == null
                ? 'Service line'
                : 'Order #${item.serviceOrderId!.substring(0, 8)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        if (showProfit) ...[
          SizedBox(height: 2),
          Text(
            'Profit: ${ShopSettings.currency}${item.profit.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantityControls(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () =>
                ref.read(cartProvider.notifier).decrementQuantity(item.cartKey),
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.remove,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          InkWell(
            onTap: item.isService ? null : () => _editQuantity(context, ref),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                UnitUtils.formatWithUnit(item.quantity, item.unit),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              final success = ref
                  .read(cartProvider.notifier)
                  .incrementQuantity(item.cartKey);
              if (!success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.isService
                                ? 'Service charges can be added once per order.'
                                : !item.tracksStock
                                ? 'Quantity updated.'
                                : item.usesConversion
                                ? 'Maximum stock reached: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}.'
                                : 'Maximum stock reached!',
                          ),
                        ),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.error,
                    width: 250,
                  ),
                );
              }
            },
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.add, size: 16, color: AppColors.primaryLight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalText({TextAlign textAlign = TextAlign.right}) {
    return Text(
      '${ShopSettings.currency}${item.total.toStringAsFixed(2)}',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.primaryLight,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            MediaQuery.sizeOf(context).width <= 430 ||
            constraints.maxWidth <= 430;
        if (compact) {
          return _MobileCartItemCard(
            item: item,
            showProfit: showProfit,
            onEditQuantity: () => _editQuantity(context, ref),
            quantityControls: _buildQuantityControls(context, ref),
          );
        }

        final icon = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color:
                (item.isService
                        ? Theme.of(context).colorScheme.secondary
                        : AppColors.primary)
                    .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            item.isService
                ? Icons.design_services_rounded
                : Icons.inventory_2_outlined,
            color: item.isService
                ? Theme.of(context).colorScheme.secondary
                : AppColors.primaryLight,
            size: 20,
          ),
        );

        return Row(
          children: [
            icon,
            SizedBox(width: 12),
            Expanded(child: _buildDetails(context)),
            _buildQuantityControls(context, ref),
            SizedBox(width: 12),
            SizedBox(width: 68, child: _buildTotalText()),
          ],
        );
      },
    );
  }
}

class _MobileCartItemCard extends StatelessWidget {
  final CartItem item;
  final bool showProfit;
  final VoidCallback onEditQuantity;
  final Widget quantityControls;

  const _MobileCartItemCard({
    required this.item,
    required this.showProfit,
    required this.onEditQuantity,
    required this.quantityControls,
  });

  @override
  Widget build(BuildContext context) {
    final itemName = _cartItemDisplayName(item);
    final accent = item.isService
        ? Theme.of(context).colorScheme.secondary
        : AppColors.primaryLight;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.isService
                      ? Icons.design_services_rounded
                      : Icons.inventory_2_outlined,
                  color: accent,
                  size: 19,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      item.isService
                          ? 'Service line'
                          : '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} ${UnitUtils.priceLabel(item.unit)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CartMetaChip(
                icon: Icons.sell_outlined,
                label:
                    '${ShopSettings.currency}${item.total.toStringAsFixed(2)}',
                color: AppColors.primaryLight,
              ),
              if (showProfit)
                _CartMetaChip(
                  icon: Icons.trending_up,
                  label:
                      'Profit ${ShopSettings.currency}${item.profit.toStringAsFixed(2)}',
                  color: AppColors.success,
                ),
              if (!item.isService && item.tracksStock)
                _CartMetaChip(
                  icon: Icons.inventory_outlined,
                  label: item.usesConversion
                      ? '${UnitUtils.formatWithUnit(item.maxStock, item.unit)} available'
                      : '${UnitUtils.formatWithUnit(item.maxStock, item.unit)} in stock',
                )
              else if (!item.isService)
                const _CartMetaChip(
                  icon: Icons.all_inclusive,
                  label: 'No stock limit',
                )
              else if (item.serviceOrderId != null)
                _CartMetaChip(
                  icon: Icons.assignment_outlined,
                  label: 'Order #${item.serviceOrderId!.substring(0, 8)}',
                ),
              if (item.variantName != null &&
                  item.variantName!.trim().isNotEmpty)
                _CartMetaChip(
                  icon: Icons.category_outlined,
                  label: item.variantName!.trim(),
                ),
              if (item.variantColorName != null &&
                  item.variantColorName!.trim().isNotEmpty)
                _CartMetaChip(
                  icon: Icons.palette_outlined,
                  label: item.variantColorName!.trim(),
                ),
            ],
          ),
          SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: item.isService
                      ? Text(
                          UnitUtils.formatWithUnit(item.quantity, item.unit),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : InkWell(
                          onTap: onEditQuantity,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              UnitUtils.formatWithUnit(
                                item.quantity,
                                item.unit,
                              ),
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                ),
                quantityControls,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _CartMetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: chipColor),
          SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: chipColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String title;
  final String? color;
  final String? categoryName;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.title,
    this.color,
    this.categoryName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              color: isSelected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? accent.withValues(alpha: 0.4)
                    : (isDark ? AppColors.darkBorder : AppColors.border),
                width: 1,
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? accent
                    : (isDark
                          ? AppColors.darkTextPrimary
                          : Theme.of(context).colorScheme.onSurface),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  final String? categoryName;
  final bool isOutOfStock;
  final double size;

  const _ProductImagePlaceholder({
    required this.categoryName,
    required this.isOutOfStock,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final radius = size <= 44 ? AppRadius.sm : AppRadius.lg;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            (Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkSurfaceHighlight
                    : Theme.of(context).colorScheme.surfaceContainerHighest)
                .withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (size > 44)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Icon(
        CategoryIconUtils.iconFor(categoryName),
        size: size <= 44 ? 22 : 32,
        color: isOutOfStock
            ? (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextMuted
                      : Theme.of(context).colorScheme.onSurfaceVariant)
                  .withValues(alpha: 0.4)
            : (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkAccent
                      : AppColors.primaryLight)
                  .withValues(alpha: 0.9),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    this.categoryName,
    required this.onTap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  Widget _buildProductImage(String imagePath, bool isOutOfStock) {
    if (ProductImageUploadService.isRemoteImage(imagePath)) {
      return Image.network(
        imagePath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Center(
          child: _ProductImagePlaceholder(
            categoryName: widget.categoryName,
            isOutOfStock: isOutOfStock,
          ),
        ),
      );
    }

    return Image.file(
      File(imagePath),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => Center(
        child: _ProductImagePlaceholder(
          categoryName: widget.categoryName,
          isOutOfStock: isOutOfStock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final isVariantResult =
        product['result_type'] == 'variant' &&
        product['matched_variant_id'] != null;
    final variantName = product['matched_variant_name'] as String?;
    final displayName =
        isVariantResult && variantName?.trim().isNotEmpty == true
        ? '${product['name']} - ${variantName!.trim()}'
        : product['name'] as String? ?? '';
    final displayPrice = isVariantResult
        ? (product['matched_variant_price'] as num? ??
                  product['price'] as num? ??
                  0)
              .toDouble()
        : (product['price'] as num? ?? 0).toDouble();
    final stock = isVariantResult
        ? (product['matched_variant_stock'] as num? ?? 0).toDouble()
        : (product['stock'] as num? ?? 0).toDouble();
    final lowStock = isVariantResult
        ? (product['matched_variant_low_stock'] as num? ?? 5).toDouble()
        : (product['low_stock'] as num? ?? 5).toDouble();
    final saleUnit = UnitUtils.saleUnitForProduct(product);
    final saleToStockFactor = UnitUtils.saleToStockFactor(product);
    final tracksStock = UnitUtils.tracksStock(product);
    final saleStock = saleToStockFactor > 0
        ? (stock / saleToStockFactor)
        : stock;
    final isLowStock = tracksStock && stock <= lowStock;
    final isOutOfStock = tracksStock && stock <= 0;

    final stockBadgeColor = isOutOfStock
        ? AppColors.error
        : isLowStock
        ? AppColors.warning
        : AppColors.success;

    final stockLabel = !tracksStock
        ? 'No stock limit'
        : isOutOfStock
        ? 'Out of stock'
        : UnitUtils.formatWithUnit(saleStock, saleUnit);

    final imagePath = product['image_url'] as String?;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isOutOfStock
          ? (isDark
                ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.5)
                : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45))
          : (isDark ? AppColors.darkSurface : AppColors.surface),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: isOutOfStock ? null : widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isOutOfStock
                  ? (isDark
                        ? AppColors.darkBorder.withValues(alpha: 0.3)
                        : AppColors.border.withValues(alpha: 0.35))
                  : (isDark ? AppColors.darkBorder : AppColors.border),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: hasImage
                          ? _buildProductImage(imagePath, isOutOfStock)
                          : _ProductImagePlaceholder(
                              categoryName: widget.categoryName,
                              isOutOfStock: isOutOfStock,
                              size: 40,
                            ),
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          '${ShopSettings.currency}${displayPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: stockBadgeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Text(
                      stockLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: stockBadgeColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String title;
  final String value;
  final bool isDiscount;

  const _SummaryRow({
    required this.title,
    required this.value,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDiscount
                  ? AppColors.warning
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _PromotionBreakdown extends StatelessWidget {
  final List<Map<String, dynamic>> promotions;
  final bool compact;

  const _PromotionBreakdown({required this.promotions, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (promotions.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = promotions
        .map((promotion) {
          final name = promotion['name']?.toString() ?? 'Promotion';
          final amount = (promotion['amount'] as num?)?.toDouble() ?? 0;
          return '$name - ${ShopSettings.currency}${amount.toStringAsFixed(2)}';
        })
        .join(', ');
    return Row(
      children: [
        Icon(
          Icons.local_offer_outlined,
          size: compact ? 13 : 15,
          color: AppColors.success,
        ),
        SizedBox(width: compact ? 4 : 6),
        Expanded(
          child: Text(
            text,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.success,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactCartAmount extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool isPrimary;

  const _CompactCartAmount({
    required this.label,
    required this.value,
    required this.valueColor,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: isPrimary ? 15 : 12,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final bool isDark;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.55)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.55)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color:
                accent ??
                (isDark
                    ? AppColors.darkAccent
                    : Theme.of(context).colorScheme.primary),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextPrimary
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  final bool isDark;

  const _StatCardSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.35)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 18, height: 18, color: Colors.transparent),
          SizedBox(height: 8),
          Container(
            width: 40,
            height: 16,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkTextMuted.withValues(alpha: 0.2)
                  : Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SizedBox(height: 6),
          Container(
            width: 28,
            height: 10,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkTextMuted.withValues(alpha: 0.15)
                  : Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSaleRow extends StatelessWidget {
  final String paymentType;
  final String total;
  final String time;
  final String items;
  final bool isDark;

  const _RecentSaleRow({
    required this.paymentType,
    required this.total,
    required this.time,
    required this.items,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.4)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.45)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
                  (isDark
                          ? AppColors.darkAccent
                          : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.receipt_outlined,
              size: 18,
              color: isDark
                  ? AppColors.darkAccent
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  items,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextMuted
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3),
              Text(
                paymentType,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkAccentSoft
                      : Theme.of(context).colorScheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSaleRowSkeleton extends StatelessWidget {
  final bool isDark;

  const _RecentSaleRowSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.25)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkTextMuted.withValues(alpha: 0.15)
                  : Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkTextMuted.withValues(alpha: 0.2)
                        : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SizedBox(height: 6),
                Container(
                  width: 100,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkTextMuted.withValues(alpha: 0.15)
                        : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
