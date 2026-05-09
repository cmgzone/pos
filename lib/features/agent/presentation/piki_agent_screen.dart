import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/openrouter_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../app/app_shell.dart';
import '../../sales/data/cart_provider.dart';
import '../data/piki_models.dart';
import '../data/piki_provider.dart';
import 'piki_message_bubble.dart';

class PikiAgentScreen extends ConsumerStatefulWidget {
  const PikiAgentScreen({super.key});

  @override
  ConsumerState<PikiAgentScreen> createState() => _PikiAgentScreenState();
}

class _PikiAgentScreenState extends ConsumerState<PikiAgentScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  static const _quickActions = [
    {'icon': Icons.inventory_2_outlined, 'label': 'Restock Items', 'prompt': 'Create a restock list for low stock items'},
    {'icon': Icons.bar_chart_rounded, 'label': "Today's Summary", 'prompt': "Show today's sales summary"},
    {'icon': Icons.description_outlined, 'label': 'Create Report', 'prompt': 'Show a sales report'},
    {'icon': Icons.warning_amber_rounded, 'label': 'Low Stock', 'prompt': 'Check low stock items'},
    {'icon': Icons.event_busy_rounded, 'label': 'Expiry Check', 'prompt': 'Check expiring products'},
    {'icon': Icons.trending_up_rounded, 'label': 'Profit', 'prompt': 'Show profit summary'},
    {'icon': Icons.people_alt_outlined, 'label': 'Top Debtors', 'prompt': 'Show top customers who owe money'},
    {'icon': Icons.leaderboard_rounded, 'label': 'Top Products', 'prompt': 'Show top selling products'},
    {'icon': Icons.money_off_rounded, 'label': 'Expenses', 'prompt': 'Show expense summary'},
    {'icon': Icons.local_shipping_outlined, 'label': 'Stock In', 'prompt': 'Show recent purchase history'},
  ];

  static const _sellQuickActions = [
    {'icon': Icons.shopping_cart_checkout_rounded, 'label': 'Checkout', 'prompt': 'checkout'},
    {'icon': Icons.delete_sweep_rounded, 'label': 'Clear Cart', 'prompt': 'clear cart'},
    {'icon': Icons.search_rounded, 'label': 'Find Product', 'prompt': 'sell '},
  ];

  @override
  void initState() {
    super.initState();
    _refreshAiStatus();
  }

  Future<void> _refreshAiStatus() async {
    await OpenRouterService.refreshConfig();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(pikiMessagesProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(pikiMessagesProvider);
    final status = ref.watch(pikiStatusProvider);
    final mode = ref.watch(pikiModeProvider);
    final insight = ref.watch(pikiInsightProvider);
    final cart = ref.watch(cartProvider);
    final isMobile = MediaQuery.of(context).size.width < 800;

    // Navigate to POS when sell mode triggers checkout
    ref.listen(pikiNavigateProvider, (_, next) {
      if (next == PikiNavTarget.pos) {
        ref.read(pikiNavigateProvider.notifier).state = PikiNavTarget.none;
        AppShell.selectIndex(0);
      }
    });

    // Auto-scroll when messages change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  AppShell.scaffoldKey.currentState?.openDrawer();
                },
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Text('AI Agent'),
        actions: [
          _AiIndicator(status: status),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // ── Chat area ──────────────────────────────────────────────
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(mode)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => PikiMessageBubble(
                      message: messages[index],
                      onSendPrompt: (prompt) {
                        ref.read(pikiMessagesProvider.notifier).sendMessage(prompt);
                        _scrollToBottom();
                      },
                    ),
                  ),
          ),

          // ── Insight / Cart bar ────────────────────────────────────
          if (mode == PikiMode.sell && cart.isNotEmpty)
            _SellCartBar(
              cart: cart,
              onCheckout: () {
                ref.read(pikiMessagesProvider.notifier).sendMessage('checkout');
              },
            )
          else if (insight != null && insight.isNotEmpty &&
              mode != PikiMode.sell)
            _InsightBar(insight: insight),

          // ── Quick actions ───────────────────────────────────────
          _QuickActions(
            actions: mode == PikiMode.sell ? _sellQuickActions : _quickActions,
            onTap: (prompt) {
              ref.read(pikiMessagesProvider.notifier).sendMessage(prompt);
              _scrollToBottom();
            },
          ),

          // ── Mode toggle + input bar ──────────────────────────────
          _BottomBar(
            controller: _controller,
            focusNode: _focusNode,
            mode: mode,
            onSend: _send,
            onSelectMode: (m) =>
                ref.read(pikiModeProvider.notifier).state = m,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(PikiMode mode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: mode == PikiMode.sell
                      ? [const Color(0xFF00C896), const Color(0xFF00A8FF)]
                      : [AppColors.primary, const Color(0xFFFF7E67)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (mode == PikiMode.sell
                            ? const Color(0xFF00C896)
                            : AppColors.primary)
                        .withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  mode == PikiMode.sell
                      ? Icons.point_of_sale_rounded
                      : null,
                  color: Colors.white,
                  size: 36,
                  semanticLabel: mode == PikiMode.sell ? 'Sell' : null,
                ),
              ),
            ),
            if (mode != PikiMode.sell)
              const Center(
                child: Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 36,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              mode == PikiMode.sell ? 'Sell Mode' : 'Piki AI Assistant',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mode == PikiMode.sell
                  ? 'Say what to sell — e.g. "2 Fanta"\nThen say "checkout" to go to POS.'
                  : 'AI can analyze, plan, and complete\ntasks for your business.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: (mode == PikiMode.plan
                        ? AppColors.secondary
                        : AppColors.warning)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: (mode == PikiMode.plan
                          ? AppColors.secondary
                          : AppColors.warning)
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    mode == PikiMode.plan
                        ? Icons.route_rounded
                        : Icons.bolt_rounded,
                    size: 16,
                    color: mode == PikiMode.plan
                        ? AppColors.secondary
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    mode == PikiMode.plan ? 'Plan Mode' : 'Fast Mode',
                    style: TextStyle(
                      color: mode == PikiMode.plan
                          ? AppColors.secondary
                          : AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status badge ───────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final AgentStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    switch (status) {
      case AgentStatus.thinking:
        color = AppColors.warning;
        label = 'Thinking';
        icon = Icons.psychology_rounded;
      case AgentStatus.working:
        color = AppColors.secondary;
        label = 'Working';
        icon = Icons.auto_awesome;
      case AgentStatus.completed:
        color = AppColors.success;
        label = 'Done';
        icon = Icons.check_circle;
      case AgentStatus.idle:
        color = AppColors.textSecondary;
        label = 'Ready';
        icon = Icons.circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiIndicator extends StatelessWidget {
  final AgentStatus status;

  const _AiIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final aiEnabled = OpenRouterService.isEnabled;
    final modelName = OpenRouterService.modelName;
    final shortModel = modelName.contains('/')
        ? modelName.split('/').last
        : modelName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBadge(status: status),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: aiEnabled
                ? const Color(0xFF6B4EE6).withValues(alpha: 0.12)
                : AppColors.surfaceHighlight,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: aiEnabled
                  ? const Color(0xFF6B4EE6).withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                aiEnabled ? Icons.auto_awesome_rounded : Icons.offline_bolt,
                size: 14,
                color: aiEnabled
                    ? const Color(0xFF8B6CFF)
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                aiEnabled ? 'AI ${shortModel.toUpperCase()}' : 'Local Only',
                style: TextStyle(
                  color: aiEnabled
                      ? const Color(0xFF8B6CFF)
                      : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Insight bar ────────────────────────────────────────────────────────────

class _InsightBar extends StatelessWidget {
  final String insight;
  const _InsightBar({required this.insight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
            ).createShader(bounds),
            child: const Icon(
              Icons.auto_awesome,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Insight:',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              insight,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            'View Details',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
        ],
      ),
    );
  }
}

// ─── Quick action chips ─────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final List<Map<String, dynamic>> actions;
  final ValueChanged<String> onTap;

  const _QuickActions({required this.actions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            avatar: Icon(
              action['icon'] as IconData,
              size: 16,
              color: AppColors.textPrimary,
            ),
            label: Text(
              action['label'] as String,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.surfaceHighlight,
            side: const BorderSide(color: AppColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onPressed: () => onTap(action['prompt'] as String),
          );
        },
      ),
    );
  }
}

// ─── Bottom input bar ───────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final PikiMode mode;
  final VoidCallback onSend;
  final ValueChanged<PikiMode> onSelectMode;

  const _BottomBar({
    required this.controller,
    required this.focusNode,
    required this.mode,
    required this.onSend,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode toggle row
            Row(
              children: [
                _ModeToggle(
                  label: 'Plan',
                  icon: Icons.route_rounded,
                  isActive: mode == PikiMode.plan,
                  color: AppColors.secondary,
                  onTap: () => onSelectMode(PikiMode.plan),
                ),
                const SizedBox(width: 8),
                _ModeToggle(
                  label: 'Fast',
                  icon: Icons.bolt_rounded,
                  isActive: mode == PikiMode.fast,
                  color: AppColors.warning,
                  onTap: () => onSelectMode(PikiMode.fast),
                ),
                const SizedBox(width: 8),
                _ModeToggle(
                  label: 'Sell',
                  icon: Icons.point_of_sale_rounded,
                  isActive: mode == PikiMode.sell,
                  color: const Color(0xFF00C896),
                  onTap: () => onSelectMode(PikiMode.sell),
                ),
                const Spacer(),
                Text(
                  mode == PikiMode.plan
                      ? 'Plans step-by-step'
                      : mode == PikiMode.fast
                          ? 'Instant results'
                          : 'Voice-to-cart POS',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: mode == PikiMode.sell
                          ? 'Say "2 Fanta" or "checkout"...'
                          : 'Ask Piki AI...',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceHighlight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.mic_rounded,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {},
                      ),
                    ),
                    onSubmitted: (_) => onSend(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFFCC2250)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: onSend,
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _ModeToggle({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? color : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sell Mode cart summary bar ─────────────────────────────────────────────

class _SellCartBar extends StatelessWidget {
  final List<CartItem> cart;
  final VoidCallback onCheckout;

  const _SellCartBar({required this.cart, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final itemCount = cart.fold<double>(0, (s, i) => s + i.quantity);
    final total = cart.fold<double>(0, (s, i) => s + i.total);
    final countStr = itemCount == itemCount.roundToDouble()
        ? itemCount.toInt().toString()
        : itemCount.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF003D2B),
        border: Border(
          top: BorderSide(color: Color(0xFF00C896), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_cart_rounded,
                    size: 14, color: Color(0xFF00C896)),
                const SizedBox(width: 6),
                Text(
                  '$countStr item${itemCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Total: $currency${total.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onCheckout,
            icon: const Icon(Icons.point_of_sale_rounded, size: 16),
            label: const Text('Checkout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
