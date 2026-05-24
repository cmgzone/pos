import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/cash_drawer_service.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/pos_payment_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../agent/data/piki_models.dart';
import '../../agent/data/piki_provider.dart';
import '../../products/data/product_provider.dart';
import '../../products/data/product_repository.dart';
import '../../products/data/product_variant_repository.dart';
import '../../shifts/data/shift_provider.dart';
import '../../shifts/data/shift_preferences_service.dart';
import '../../shifts/data/shift_repository.dart';
import '../../shifts/presentation/shift_auto_open_dialog.dart';
import '../../training/widgets/training_anchor.dart';

import '../data/cart_provider.dart';
import '../data/held_sale_provider.dart';
import '../data/held_sale_repository.dart';
import '../data/sale_repository.dart';
import '../../app/app_shell.dart';
import '../../services/data/service_repository.dart';
import '../../services/data/service_provider.dart';

import 'barcode_scanner.dart';
import 'payment_checkout_dialog.dart';
import 'receipt_service.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final cartCount = ref.watch(cartProvider).length;
    final cashierName = SessionService.currentUserName;
    final cashierRole = RolePermissions.label(SessionService.currentUserRole);
    final syncState = ref.watch(syncControllerProvider);
    final currentShiftAsync = ref.watch(currentShiftProvider);
    final canOpenShifts = SessionService.canAccessFeature(
      UserAccessProfile.featureShifts,
    );

    ref.listen(pikiNavigateProvider, (_, next) {
      if (next != PikiNavTarget.pos || !isMobile) return;
      ref.read(pikiNavigateProvider.notifier).state = PikiNavTarget.none;
      if (ref.read(cartProvider).isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _showMobileCartSheet(context);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
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
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
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
          const SizedBox(width: 8),
          if (canOpenShifts && !isMobile) ...[
            _ShiftStatusChip(shiftAsync: currentShiftAsync),
            const SizedBox(width: 8),
          ],
          if (!isMobile) ...[
            _LicenseIndicatorChip(state: syncState),
            const SizedBox(width: 8),
            _SyncIndicatorChip(state: syncState),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                cashierName.isEmpty
                    ? '?'
                    : cashierName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cashierName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  cashierRole,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive: side-by-side on wide screens, stacked on narrow
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(flex: 7, child: _ProductSide()),
                Container(width: 1, color: AppColors.border),
                SizedBox(
                  width: 380,
                  child: TrainingAnchor(id: 'pos.cart', child: _CartSide()),
                ),
              ],
            );
          } else {
            return _ProductSide(); // Mobile: full screen products + FAB for cart
          }
        },
      ),
      floatingActionButton: isMobile
          ? TrainingAnchor(
              id: 'pos.cart',
              child: FloatingActionButton.extended(
                onPressed: () => _showMobileCartSheet(context),
                backgroundColor: cartCount > 0
                    ? AppColors.success
                    : AppColors.surfaceHighlight,
                foregroundColor: Colors.white,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_cart_checkout_rounded),
                    if (cartCount > 0)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$cartCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                label: Text(cartCount > 0 ? 'Checkout' : 'Cart'),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _showMobileCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.92,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(child: _CartSide()),
            ],
          ),
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

  const _SyncIndicatorChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final config = _resolveIndicatorStyle(state);

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
          const SizedBox(width: 6),
          Text(
            config.label,
            style: TextStyle(color: config.color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  _SyncIndicatorStyle _resolveIndicatorStyle(SyncState state) {
    switch (state.indicator) {
      case SyncIndicatorState.localOnly:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_off,
          color: AppColors.textSecondary,
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

  const _ShiftStatusChip({required this.shiftAsync});

  @override
  Widget build(BuildContext context) {
    final shift = shiftAsync.valueOrNull;
    final isOpen = shift != null;

    return TextButton.icon(
      onPressed: () => AppShell.selectIndex(10),
      icon: shiftAsync.isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isOpen ? Icons.timer_rounded : Icons.lock_clock_outlined,
              size: 18,
              color: isOpen ? AppColors.success : AppColors.warning,
            ),
      label: Text(
        shiftAsync.isLoading
            ? 'Shift...'
            : isOpen
            ? 'Shift Open'
            : 'Open Shift',
        style: TextStyle(
          color: isOpen ? AppColors.success : AppColors.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

class _LicenseIndicatorChip extends StatelessWidget {
  final SyncState state;

  const _LicenseIndicatorChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final license = state.licenseSnapshot;
    final color = switch (license.accessStatus) {
      LicenseAccessStatus.active => AppColors.success,
      LicenseAccessStatus.grace => AppColors.warning,
      LicenseAccessStatus.expired ||
      LicenseAccessStatus.invalid => AppColors.error,
      LicenseAccessStatus.localOnly => AppColors.textSecondary,
    };
    final icon = switch (license.accessStatus) {
      LicenseAccessStatus.active => Icons.verified_outlined,
      LicenseAccessStatus.grace => Icons.schedule_outlined,
      LicenseAccessStatus.expired => Icons.lock_clock_outlined,
      LicenseAccessStatus.invalid => Icons.gpp_bad_outlined,
      LicenseAccessStatus.localOnly => Icons.offline_bolt_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(switch (license.accessStatus) {
            LicenseAccessStatus.active => 'Active',
            LicenseAccessStatus.grace => 'Grace',
            LicenseAccessStatus.expired => 'Expired',
            LicenseAccessStatus.invalid => 'License Error',
            LicenseAccessStatus.localOnly => 'Local Only',
          }, style: TextStyle(color: color, fontSize: 12)),
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
    if (product['result_type'] != 'variant') {
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

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
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

  String _cartLabel(
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
  }) {
    final productName = product['name'] as String? ?? 'Product';
    final variantName = variant?['name'] as String? ?? '';
    if (variantName.trim().isEmpty) {
      return productName;
    }
    return '$productName - ${variantName.trim()}';
  }

  void _showAddToCartSnackBar(
    bool success,
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
  }) {
    if (!mounted) {
      return;
    }

    final label = _cartLabel(product, variant: variant);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.warning_amber,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
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

  void _addProductToCart(
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
  }) {
    final success = ref
        .read(cartProvider.notifier)
        .addProduct(product, variant: variant);
    _showAddToCartSnackBar(success, product, variant: variant);
    _clearSearch();
  }

  Future<Map<String, dynamic>?> _pickVariantForProduct(
    Map<String, dynamic> product,
  ) async {
    final variants = await ProductVariantRepository.getForProduct(
      product['id'] as String,
    );
    if (!mounted) {
      return null;
    }
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This product has no variants yet.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return null;
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Choose Variant - ${product['name']}'),
        content: SizedBox(
          width: 460,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: variants.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final variant = variants[index];
              final stock = (variant['stock'] as num? ?? 0).toDouble();
              final tracksStock = UnitUtils.tracksStock(product);
              final outOfStock = tracksStock && stock <= 0;
              return Material(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  enabled: !outOfStock,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(variant['name'] as String? ?? 'Variant'),
                  subtitle: Text(
                    '${ShopSettings.currency}${((variant['price'] as num?) ?? 0).toStringAsFixed(2)} - ${!tracksStock
                        ? 'No stock limit'
                        : outOfStock
                        ? 'Out of stock'
                        : UnitUtils.formatWithUnit(stock, UnitUtils.stockUnitForProduct(product))}',
                  ),
                  trailing: outOfStock
                      ? const Icon(Icons.block_outlined, color: AppColors.error)
                      : const Icon(Icons.chevron_right),
                  onTap: outOfStock
                      ? null
                      : () => Navigator.pop(dialogContext, variant),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleProductSelection(Map<String, dynamic> product) async {
    final matchedVariant = _matchedVariantFromSearchResult(product);
    if (matchedVariant != null) {
      _addProductToCart(product, variant: matchedVariant);
      return;
    }

    if (!_isVariantProduct(product)) {
      _addProductToCart(product);
      return;
    }

    final variant = await _pickVariantForProduct(product);
    if (variant == null) {
      return;
    }
    _addProductToCart(product, variant: variant);
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    final variant = await ProductVariantRepository.getByBarcode(barcode);
    if (variant != null) {
      final parentProduct = <String, dynamic>{
        'id': variant['product_id'],
        'name': variant['parent_product_name'],
        'price': variant['price'],
        'cost': variant['cost'],
        'stock': variant['stock'],
        'unit': variant['unit'],
        'stock_unit': variant['stock_unit'],
        'sale_unit': variant['sale_unit'],
        'sale_to_stock_factor': variant['sale_to_stock_factor'],
        'image_url': variant['image_url'],
        'category_id': variant['category_id'],
        'track_stock': variant['track_stock'],
        'has_variants': variant['has_variants'],
      };
      _addProductToCart(parentProduct, variant: variant);
      return;
    }

    final product = await ProductRepository.getByBarcode(barcode);
    if (product != null) {
      await _handleProductSelection(product);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
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
    }
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your admin has not enabled POS product or service access for this account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
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
    final isMobileDevice = Platform.isAndroid || Platform.isIOS;

    final compact = MediaQuery.sizeOf(context).width <= 520;
    final productPadding = compact ? 14.0 : 24.0;

    Widget serviceShortcut({required bool iconOnly}) {
      if (!canUseServices) {
        return const SizedBox.shrink();
      }
      if (iconOnly) {
        return Tooltip(
          message: 'Open services',
          child: Material(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _openServicesPage,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: EdgeInsets.all(compact ? 12 : 14),
                child: const Icon(
                  Icons.design_services_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        );
      }

      return OutlinedButton.icon(
        onPressed: _openServicesPage,
        icon: const Icon(Icons.design_services_outlined, size: 18),
        label: const Text('Services'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Container(
      color: AppColors.background,
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
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        autofocus: Platform.isWindows,
                        onTap: _focusSearchField,
                        onChanged: (v) =>
                            ref.read(productSearchProvider.notifier).state = v,
                        onSubmitted: (v) {
                          final code = v.trim();
                          final lower = code.toLowerCase();
                          // Only attempt barcode lookup if it looks like a barcode
                          // (not a URL or plain text search entry)
                          if (code.length >= 4 &&
                              !lower.startsWith('http') &&
                              !lower.startsWith('www.') &&
                              !lower.contains('://') &&
                              RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(code)) {
                            _handleBarcodeScan(code);
                          } else {
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _focusSearchField(),
                            );
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Search products or scan barcode...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: _clearSearch,
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (canUseServices) ...[
                      SizedBox(width: compact ? 8 : 12),
                      serviceShortcut(iconOnly: compact),
                    ],
                    if (isMobileDevice) ...[
                      SizedBox(width: compact ? 8 : 12),
                      Material(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: _openCameraScanner,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: EdgeInsets.all(compact ? 12 : 14),
                            child: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (Platform.isWindows) ...[
                  const SizedBox(height: 6),
                  Text(
                    _searchFocusNode.hasFocus
                        ? 'Scanner ready. Scan items without clicking again.'
                        : 'Click here once, then scan barcode.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: compact ? 14 : 20),

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
                          ref.read(selectedCategoryProvider.notifier).state =
                              null,
                    ),
                    ...categories.map(
                      (cat) => _CategoryChip(
                        title: cat['name'] as String,
                        color: cat['color'] as String?,
                        categoryName: cat['name'] as String?,
                        isSelected: selectedCategory == cat['id'],
                        onTap: () =>
                            ref.read(selectedCategoryProvider.notifier).state =
                                cat['id'] as String,
                      ),
                    ),
                  ],
                ),
              ),
              loading: () => const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text(
                AppErrorMessage.from(e, fallback: AppErrorMessage.loadFailed),
              ),
            ),
          ),
          SizedBox(height: compact ? 14 : 20),

          // Product grid
          Expanded(
            child: TrainingAnchor(
              id: 'pos.products',
              child: productsAsync.when(
                data: (products) {
                  final categories = categoriesAsync.valueOrNull ?? [];
                  if (products.isEmpty) {
                    return const EmptyStateWidget(
                      icon: Icons.inventory_2_outlined,
                      title: 'No products found',
                      subtitle:
                          'Try searching for something else or check your category filters.',
                    );
                  }
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: compact ? 180 : 220,
                      childAspectRatio: compact ? 0.72 : 0.82,
                      crossAxisSpacing: compact ? 12 : 16,
                      mainAxisSpacing: compact ? 12 : 16,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      // Resolve category name for icon fallback
                      final catId = product['category_id'] as String?;
                      final catName = catId != null
                          ? (categories.firstWhere(
                                  (c) => c['id'] == catId,
                                  orElse: () => {},
                                )['name']
                                as String?)
                          : null;
                      return _ProductCard(
                        product: product,
                        categoryName: catName,
                        onTap: () async {
                          await _handleProductSelection(product);
                        },
                      );
                    },
                  );
                },
                loading: () => GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: 8,
                  itemBuilder: (_, _) => Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
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
  }
}

class _ServiceOnlyPosShortcut extends StatelessWidget {
  final VoidCallback onTap;

  const _ServiceOnlyPosShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.design_services_outlined,
                  color: AppColors.secondary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Services are managed on the Services page',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open Services to create orders, quick-sell jobs, and send service charges to the cart.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open Services'),
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
    final total = ref.watch(cartTotalProvider);
    final profit = ref.watch(cartProfitProvider);
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
    final cashCheckoutBlocked =
        currentShiftAsync.isLoading ||
        (hasOpenShift && currentSummaryAsync.isLoading);

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

        return Container(
          color: AppColors.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
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
                          const SizedBox(
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
                                  : AppColors.textSecondary,
                            ),
                            label: Text(
                              heldSaleCount > 0
                                  ? 'Held ($heldSaleCount)'
                                  : 'Held',
                            ),
                          ),
                        if (cart.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _clearCurrentSale(ref),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.error,
                            ),
                            label: const Text(
                              'Clear',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isMobileCart ? 9 : 14),
                      decoration: BoxDecoration(
                        color: hasOpenShift
                            ? AppColors.success.withValues(alpha: 0.10)
                            : AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          isMobileCart ? 10 : 14,
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
                          SizedBox(width: isMobileCart ? 8 : 12),
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
                                  const SizedBox(height: 2),
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
                                  horizontal: isMobileCart ? 6 : 8,
                                  vertical: isMobileCart ? 4 : 8,
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
              const Divider(height: 1),
              Expanded(
                child: cart.isEmpty
                    ? _buildEmptyCartState(
                        context,
                        ref,
                        heldSaleCount: heldSaleCount,
                        holdsLoading: heldSalesAsync.isLoading,
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(isMobileCart ? 12 : 16),
                        itemCount: cart.length,
                        separatorBuilder: (_, _) => isMobileCart
                            ? const SizedBox(height: 10)
                            : const Divider(height: 24),
                        itemBuilder: (context, index) {
                          final item = cart[index];
                          return _CartItemRow(item: item);
                        },
                      ),
              ),
              if (cart.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(isMobileCart ? 10 : 24),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceHighlight,
                    border: Border(top: BorderSide(color: AppColors.border)),
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
                                    valueColor: AppColors.success,
                                    isPrimary: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _CompactCartAmount(
                                    label: 'Profit',
                                    value:
                                        '${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                                    valueColor: AppColors.success,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 40,
                                  child: ElevatedButton.icon(
                                    onPressed: cashCheckoutBlocked
                                        ? () => _handleBlockedCheckout(context)
                                        : () => _processCheckout(context, ref),
                                    icon: const Icon(Icons.payment, size: 16),
                                    label: const Text('Pay'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      backgroundColor: AppColors.success,
                                      textStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (discount > 0 || tax > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Subtotal ${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (tax > 0)
                                    Text(
                                      'Tax ${ShopSettings.currency}${tax.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  if (discount > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '-${ShopSettings.currency}${discount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.error,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _holdCurrentSale(context, ref),
                                    icon: const Icon(
                                      Icons.pause_circle_outline,
                                      size: 16,
                                    ),
                                    label: const Text('Hold'),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: heldSalesAsync.isLoading
                                        ? null
                                        : () => _showHeldSalesDialog(
                                            context,
                                            ref,
                                          ),
                                    icon: const Icon(
                                      Icons.layers_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      heldSaleCount > 0
                                          ? 'Held ($heldSaleCount)'
                                          : 'Held',
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      textStyle: const TextStyle(fontSize: 12),
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
                            const SizedBox(height: 8),
                            _SummaryRow(
                              title: 'Tax (${ShopSettings.taxRate}%)',
                              value:
                                  '${ShopSettings.currency}${tax.toStringAsFixed(2)}',
                            ),
                            if (discount > 0) ...[
                              const SizedBox(height: 8),
                              _SummaryRow(
                                title: 'Discount',
                                value:
                                    '-${ShopSettings.currency}${discount.toStringAsFixed(2)}',
                                isDiscount: true,
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Profit',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _holdCurrentSale(context, ref),
                                    icon: const Icon(
                                      Icons.pause_circle_outline,
                                    ),
                                    label: const Text('Hold Sale'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: heldSalesAsync.isLoading
                                        ? null
                                        : () => _showHeldSalesDialog(
                                            context,
                                            ref,
                                          ),
                                    icon: const Icon(Icons.layers_outlined),
                                    label: Text(
                                      heldSaleCount > 0
                                          ? 'Held Orders ($heldSaleCount)'
                                          : 'Held Orders',
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (heldSaleCount > 0) ...[
                              const SizedBox(height: 10),
                              Text(
                                'You have $heldSaleCount held sale${heldSaleCount == 1 ? '' : 's'} ready to resume.',
                                style: TextStyle(
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.85,
                                  ),
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: cashCheckoutBlocked
                                        ? () => _handleBlockedCheckout(context)
                                        : () => _processCheckout(context, ref),
                                    icon: const Icon(Icons.payment),
                                    label: const Text(
                                      'Checkout',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Select a payment method such as Cash, Kopesha, or Mobile Money during checkout.',
                              style: TextStyle(
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.8,
                                ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_basket_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              heldSaleCount > 0
                  ? 'Tap products to add them to your sale, or resume a held order below.'
                  : 'Ready to sell! Tap products from the grid to add them here.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (heldSaleCount > 0) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _showHeldSalesDialog(context, ref),
                icon: const Icon(Icons.layers_outlined),
                label: Text('Resume Held Sale ($heldSaleCount)'),
              ),
            ],
          ],
        ),
      ),
    );
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
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
                                const SizedBox(height: 4),
                                Text(
                                  'Resume or discard saved carts.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary.withValues(
                                      alpha: 0.85,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: heldSalesAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_off_outlined,
                                  size: 40,
                                  color: AppColors.warning,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Could not load held orders.',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppErrorMessage.from(
                                    error,
                                    fallback: AppErrorMessage.loadFailed,
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      ref.invalidate(heldSalesProvider),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Try Again'),
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
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
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
  }

  Future<String?> _showHoldNameDialog(
    BuildContext context,
    List<CartItem> cart,
  ) async {
    final controller = TextEditingController(text: _defaultHoldName(cart));

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
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
          decoration: const InputDecoration(
            labelText: 'Hold name',
            helperText: 'Use a short name so you can find it quickly later.',
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Hold'),
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Replace Current Cart?'),
        content: const Text(
          'Resuming a held sale will replace the items currently in the cart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Current Cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace Cart'),
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Discard Held Sale?'),
        content: Text(
          'Delete "$holdName" from held orders? This will not affect completed sales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _handleBlockedCheckout(BuildContext context) {
    _showSnackBar(
      context,
      'Shift status is still loading. Try the cash payment again in a moment.',
      backgroundColor: AppColors.warning,
    );
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
    final checkoutResult = await PaymentCheckoutDialog.show(
      context,
      total: total,
    );

    if (!context.mounted || checkoutResult == null) return;

    final type = checkoutResult['type'] as String;
    final customer = checkoutResult['customer'] as Map<String, dynamic>?;
    final dueDate = checkoutResult['dueDate'] as String?;

    if (type == 'kopesha') {
      // Kopesha payment - requires customer
      if (customer == null) {
        _showSnackBar(
          context,
          'Customer is required for Kopesha',
          backgroundColor: AppColors.error,
        );
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
      );
    } else if (type == 'mpesa') {
      final phoneNumber = checkoutResult['phoneNumber'] as String?;
      if (phoneNumber == null || phoneNumber.trim().isEmpty) {
        _showSnackBar(
          context,
          'M-Pesa phone number is required',
          backgroundColor: AppColors.error,
        );
        return;
      }
      await _completeMpesaCheckout(
        context,
        ref,
        phoneNumber: phoneNumber,
        customer: customer,
      );
    } else {
      // Other payment methods
      final paymentMethod =
          checkoutResult['paymentMethod'] as Map<String, dynamic>?;
      if (paymentMethod == null) return;

      final isCashDrawer = paymentMethod['is_cash_drawer'] == 1;
      final paymentName = paymentMethod['name'] as String;

      if (isCashDrawer) {
        final shift = await _requireOpenShift(context);
        final requiresManagedShift = ShiftRepository.roleRequiresManagedShift(
          SessionService.currentUserRole,
        );
        if (!context.mounted || (requiresManagedShift && shift == null)) {
          return;
        }

        final cashCheckout = await _showCashCheckoutDialog(context, total);
        if (!context.mounted || cashCheckout == null) return;

        await _completeSale(
          context,
          ref,
          paymentType: paymentName,
          isCashDrawer: true,
          isCredit: false,
          shiftId: shift?['id'] as String?,
          amountTendered: cashCheckout.amountTendered,
          changeGiven: cashCheckout.changeGiven,
          customerId: customer?['id'] as String?,
          customerName: customer?['name'] as String?,
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
        );
      }
    }
  }

  Future<void> _completeMpesaCheckout(
    BuildContext context,
    WidgetRef ref, {
    required String phoneNumber,
    Map<String, dynamic>? customer,
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
        return;
      }

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
        paymentMetadata: payment.metadata,
      );

      if (saleId != null) {
        try {
          await PosPaymentService.linkSale(
            paymentId: payment.id,
            saleId: saleId,
          );
        } catch (error) {
          if (context.mounted) {
            _showSnackBar(
              context,
              AppErrorMessage.withContext(
                error,
                prefix: 'Sale saved, but payment link sync failed.',
                fallback:
                    'Sale saved, but the payment link could not be synced.',
              ),
              backgroundColor: AppColors.warning,
            );
          }
        }
      }
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
  }) async {
    final cart = ref.read(cartProvider);
    final subtotal = ref.read(cartSubtotalProvider);
    final tax = ref.read(cartTaxProvider);
    final discount = ref.read(discountProvider);
    final total = ref.read(cartTotalProvider);

    final saleItems = cart
        .map(
          (item) => {
            'line_type': item.lineType,
            'product_id': item.productId,
            'product_name': item.productName,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'unit': item.unit,
          },
        )
        .toList();

    try {
      final saleId = await SaleRepository.createSale(
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
        paymentMetadata: paymentMetadata,
      );

      _clearCurrentSale(ref);
      ref.invalidate(filteredProductsProvider);
      invalidateShiftProviders(ref);

      // ── Mark any linked service orders as paid ─────────────────────────
      final serviceOrderIds = cart
          .where(
            (item) =>
                item.serviceOrderId != null && item.serviceOrderId!.isNotEmpty,
          )
          .map((item) => item.serviceOrderId!)
          .toSet();
      for (final orderId in serviceOrderIds) {
        await ServiceRepository.attachSaleToOrder(orderId, saleId);
      }
      if (serviceOrderIds.isNotEmpty) {
        ref.invalidate(serviceOrdersProvider);
      }
      // ──────────────────────────────────────────────────────────────────

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
        );
      }
      return saleId;
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(
          context,
          AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          backgroundColor: AppColors.error,
        );
      }
      return null;
    }
  }

  Future<void> _openCashDrawerAfterSale(
    BuildContext context,
    bool isCashDrawer,
  ) async {
    if (!isCashDrawer || !CashDrawerService.isReady) {
      return;
    }

    final result = await CashDrawerService.openAfterCashSale();
    if (!context.mounted || result.success) {
      return;
    }

    _showSnackBar(context, result.message, backgroundColor: AppColors.warning);
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
  }) {
    final isKopesha = paymentType.toLowerCase() == 'kopesha';
    final hasAmountTendered = amountTendered > 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
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
            const SizedBox(width: 12),
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
              const SizedBox(height: 12),
              Text(
                'Received: ${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Change Returned: ${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: changeGiven > 0
                      ? AppColors.primaryLight
                      : AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Sale ID: ${saleId.substring(0, 8)}...',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (customerName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Customer: $customerName',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (balanceDue > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Outstanding Kopesha: ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (dueDate != null) ...[
              const SizedBox(height: 8),
              Text(
                'Due date: $dueDate',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
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
                showTenderedBreakdown: hasAmountTendered,
              );
            },
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text('Print Receipt'),
          ),
        ],
      ),
    );
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
          final hasEnoughCash = tenderedAmount + 0.001 >= total;
          final changeGiven = hasEnoughCash ? tenderedAmount - total : 0.0;

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(Icons.payments_outlined, color: AppColors.success),
                SizedBox(width: 12),
                Text('Cash Checkout'),
              ],
            ),
            content: SizedBox(
              width: 420,
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
                        const Text(
                          'Total Due',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        tenderedAmount = double.tryParse(value.trim()) ?? 0.0;
                        errorText = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
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
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Use Exact Amount'),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                        const SizedBox(width: 12),
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
                              const SizedBox(height: 2),
                              Text(
                                '${ShopSettings.currency}${(hasEnoughCash ? changeGiven : total - tenderedAmount).toStringAsFixed(2)}',
                                style: const TextStyle(
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
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
                icon: const Icon(Icons.check_circle_outline),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                label: const Text('Complete Sale'),
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
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
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
              const SizedBox(width: 12),
              Text(
                '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.playlist_add_check_circle_outlined),
                  label: const Text('Resume'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onDiscard,
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                label: const Text(
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
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

class _CartItemRow extends ConsumerWidget {
  final CartItem item;
  const _CartItemRow({required this.item});

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
        backgroundColor: AppColors.surface,
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
            child: const Text('Cancel'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final itemName =
        item.variantName != null && item.variantName!.trim().isNotEmpty
        ? '${item.productName} - ${item.variantName!.trim()}'
        : item.productName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          itemName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          item.isService
              ? '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} service charge'
              : '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} ${UnitUtils.priceLabel(item.unit)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        if (!item.isService && item.tracksStock)
          Text(
            item.usesConversion
                ? 'In stock: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)})'
                : 'In stock: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else if (!item.isService)
          const Text(
            'No stock limit',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          )
        else
          Text(
            item.serviceOrderId == null
                ? 'Service line'
                : 'Order #${item.serviceOrderId!.substring(0, 8)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          'Profit: ${ShopSettings.currency}${item.profit.toStringAsFixed(2)}',
          style: const TextStyle(
            color: AppColors.success,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityControls(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () =>
                ref.read(cartProvider.notifier).decrementQuantity(item.cartKey),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.remove,
                size: 16,
                color: AppColors.textSecondary,
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
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
                        const Icon(
                          Icons.warning_amber,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
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
            child: const Padding(
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
      style: const TextStyle(
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
            onEditQuantity: () => _editQuantity(context, ref),
            quantityControls: _buildQuantityControls(context, ref),
          );
        }

        final icon = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (item.isService ? AppColors.secondary : AppColors.primary)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            item.isService
                ? Icons.design_services_rounded
                : Icons.inventory_2_outlined,
            color: item.isService
                ? AppColors.secondary
                : AppColors.primaryLight,
            size: 20,
          ),
        );

        return Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(child: _buildDetails()),
            _buildQuantityControls(context, ref),
            const SizedBox(width: 12),
            SizedBox(width: 68, child: _buildTotalText()),
          ],
        );
      },
    );
  }
}

class _MobileCartItemCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback onEditQuantity;
  final Widget quantityControls;

  const _MobileCartItemCard({
    required this.item,
    required this.onEditQuantity,
    required this.quantityControls,
  });

  @override
  Widget build(BuildContext context) {
    final itemName =
        item.variantName != null && item.variantName!.trim().isNotEmpty
        ? '${item.productName} - ${item.variantName!.trim()}'
        : item.productName;
    final accent = item.isService
        ? AppColors.secondary
        : AppColors.primaryLight;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.isService
                          ? 'Service line'
                          : '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} ${UnitUtils.priceLabel(item.unit)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: item.isService
                      ? Text(
                          UnitUtils.formatWithUnit(item.quantity, item.unit),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
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
    final chipColor = color ?? AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: chipColor),
          const SizedBox(width: 5),
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
    // Resolve category color
    Color? accentColor;
    if (color != null) {
      try {
        accentColor = Color(int.parse(color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    final chipColor = accentColor ?? AppColors.primary;
    final icon = CategoryIconUtils.iconFor(categoryName ?? title);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: isSelected
            ? chipColor
            : AppColors.surfaceHighlight.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? chipColor : Colors.black).withValues(
                    alpha: isSelected ? 0.22 : 0.12,
                  ),
                  blurRadius: isSelected ? 20 : 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? Colors.white
                      : (accentColor ?? AppColors.textSecondary),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  bool _isHovered = false;
  bool _isPressed = false;

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
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final saleToStockFactor = UnitUtils.saleToStockFactor(product);
    final tracksStock = UnitUtils.tracksStock(product);
    final saleStock = saleToStockFactor > 0
        ? (stock / saleToStockFactor)
        : stock;
    final usesConversion = saleUnit != stockUnit;
    final isLowStock = tracksStock && stock <= lowStock;
    final isOutOfStock = tracksStock && stock <= 0;

    // Aesthetic Colors based on Velvet Night Theme
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
    final hasImage =
        imagePath != null &&
        imagePath.isNotEmpty &&
        File(imagePath).existsSync();

    final scale = _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0);

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Opacity(
        opacity: isOutOfStock ? 0.72 : 1,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: isOutOfStock ? null : widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                // Glassmorphism background
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surface.withValues(alpha: 0.9),
                    AppColors.surfaceHighlight.withValues(alpha: 0.7),
                  ],
                ),
                boxShadow: [
                  if (_isHovered)
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                ],
                border: Border.all(
                  color: _isHovered
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.border.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image Section with Glass Badge
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: hasImage
                                      ? Colors.transparent
                                      : AppColors.background.withValues(
                                          alpha: 0.5,
                                        ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: hasImage
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.file(
                                          File(imagePath),
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit: BoxFit
                                              .cover, // Better for modern cards
                                          alignment: Alignment.center,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      )
                                    : Center(
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceHighlight
                                                .withValues(alpha: 0.8),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.2,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            CategoryIconUtils.iconFor(
                                              widget.categoryName,
                                            ),
                                            size: 32,
                                            color: isOutOfStock
                                                ? AppColors.textSecondary
                                                      .withValues(alpha: 0.4)
                                                : AppColors.primaryLight
                                                      .withValues(alpha: 0.9),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            // Glass badge
                            Positioned(
                              top: 8,
                              right: 8,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 10,
                                    sigmaY: 10,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: stockBadgeColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: stockBadgeColor.withValues(
                                          alpha: 0.5,
                                        ),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      stockLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: stockBadgeColor,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Text Section
                      if (product['brand'] != null &&
                          (product['brand'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            (product['brand'] as String).toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${ShopSettings.currency}${displayPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color:
                                  AppColors.secondary, // Cyber mint for price
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '/${UnitUtils.priceLabel(saleUnit)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (usesConversion) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Stocked: ${UnitUtils.formatWithUnit(stock, stockUnit)}',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
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
        Text(title, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            color: isDiscount ? AppColors.warning : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: isPrimary ? 15 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
