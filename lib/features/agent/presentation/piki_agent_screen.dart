import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/services/openrouter_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/smart_import_preview_dialog.dart';
import '../../app/app_shell.dart';
import '../../sales/data/cart_provider.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/piki_models.dart';
import '../data/piki_provider.dart';
import 'piki_message_bubble.dart';

enum _PikiAttachmentAction { cameraPhoto, galleryPhoto, smartUpload }

enum _PikiPendingAttachmentKind { file, image }

class _PikiPendingAttachment {
  final _PikiPendingAttachmentKind kind;
  final SpreadsheetFileRows? file;
  final String? imagePath;
  final String fileName;
  final int? sizeBytes;
  final String sourceLabel;

  const _PikiPendingAttachment._({
    required this.kind,
    required this.fileName,
    required this.sourceLabel,
    this.file,
    this.imagePath,
    this.sizeBytes,
  });

  factory _PikiPendingAttachment.file(SpreadsheetFileRows file) {
    return _PikiPendingAttachment._(
      kind: _PikiPendingAttachmentKind.file,
      file: file,
      fileName: file.fileName,
      sizeBytes: file.bytes?.length,
      sourceLabel: 'file',
    );
  }

  factory _PikiPendingAttachment.image({
    required String imagePath,
    required String fileName,
    required String sourceLabel,
    int? sizeBytes,
  }) {
    return _PikiPendingAttachment._(
      kind: _PikiPendingAttachmentKind.image,
      imagePath: imagePath,
      fileName: fileName,
      sourceLabel: sourceLabel,
      sizeBytes: sizeBytes,
    );
  }

  String get typeLabel => kind == _PikiPendingAttachmentKind.file
      ? 'Smart upload'
      : sourceLabel == 'camera'
      ? 'Camera photo'
      : 'Photo';

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return '';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

class PikiAgentScreen extends ConsumerStatefulWidget {
  const PikiAgentScreen({super.key});

  @override
  ConsumerState<PikiAgentScreen> createState() => _PikiAgentScreenState();
}

class _PikiAgentScreenState extends ConsumerState<PikiAgentScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isListening = false;
  bool _voiceBusy = false;
  bool _imageBusy = false;
  bool _fileImportBusy = false;
  bool _autoListening = false;
  bool _autoLoopRunning = false;
  int _autoListenToken = 0;
  final _pendingAttachments = <_PikiPendingAttachment>[];

  static const _autoListenWindow = Duration(seconds: 5);
  static const _autoListenRestartDelay = Duration(milliseconds: 650);

  static const _quickActions = [
    {
      'icon': Icons.inventory_2_outlined,
      'label': 'Restock Items',
      'prompt': 'Create a restock list for low stock items',
    },
    {
      'icon': Icons.bar_chart_rounded,
      'label': "Today's Summary",
      'prompt': "Show today's sales summary",
    },
    {
      'icon': Icons.assignment_outlined,
      'label': 'Catalog Orders',
      'prompt': 'Show pending catalog orders',
    },
    {
      'icon': Icons.upload_file_outlined,
      'label': 'Smart Upload',
      'prompt': 'upload file to piki',
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'label': 'Proactive Check',
      'prompt': 'run proactive check',
    },
    {
      'icon': Icons.description_outlined,
      'label': 'Create Report',
      'prompt': 'Show a sales report',
    },
    {
      'icon': Icons.warning_amber_rounded,
      'label': 'Low Stock',
      'prompt': 'Check low stock items',
    },
    {
      'icon': Icons.event_busy_rounded,
      'label': 'Expiry Check',
      'prompt': 'Check expiring products',
    },
    {
      'icon': Icons.trending_up_rounded,
      'label': 'Profit',
      'prompt': 'Show profit summary',
    },
    {
      'icon': Icons.people_alt_outlined,
      'label': 'Top Debtors',
      'prompt': 'Show top customers who owe money',
    },
    {
      'icon': Icons.leaderboard_rounded,
      'label': 'Top Products',
      'prompt': 'Show top selling products',
    },
    {
      'icon': Icons.money_off_rounded,
      'label': 'Expenses',
      'prompt': 'Show expense summary',
    },
    {
      'icon': Icons.local_shipping_outlined,
      'label': 'Stock In',
      'prompt': 'Show recent purchase history',
    },
  ];

  static const _sellQuickActions = [
    {
      'icon': Icons.shopping_cart_checkout_rounded,
      'label': 'Checkout',
      'prompt': 'checkout',
    },
    {
      'icon': Icons.delete_sweep_rounded,
      'label': 'Clear Cart',
      'prompt': 'clear cart',
    },
    {
      'icon': Icons.pause_circle_outline,
      'label': 'Hold Sale',
      'prompt': 'hold sale',
    },
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
    _autoListenToken++;
    unawaited(SpeechService.stopListening());
    unawaited(SpeechService.stopPlayback());
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    unawaited(_sendInternal());
  }

  Future<void> _sendInternal({bool speakResponse = false}) async {
    final text = _controller.text.trim();
    final attachments = List<_PikiPendingAttachment>.from(_pendingAttachments);
    if (text.isEmpty && attachments.isEmpty) return;

    if (attachments.isNotEmpty) {
      final hasFile = attachments.any(
        (item) => item.kind == _PikiPendingAttachmentKind.file,
      );
      final hasImage = attachments.any(
        (item) => item.kind == _PikiPendingAttachmentKind.image,
      );
      setState(() {
        _pendingAttachments.clear();
        if (hasFile) _fileImportBusy = true;
        if (hasImage) _imageBusy = true;
      });
      _controller.clear();
      try {
        for (final attachment in attachments) {
          if (attachment.kind == _PikiPendingAttachmentKind.file) {
            final file = attachment.file;
            if (file == null) continue;
            await ref
                .read(pikiMessagesProvider.notifier)
                .importSmartFileAttachment(
                  file: file,
                  instruction: text,
                  confirmPlan: _confirmSmartImportPlan,
                );
          } else {
            final imagePath = attachment.imagePath;
            if (imagePath == null) continue;
            await ref
                .read(pikiMessagesProvider.notifier)
                .analyzeImage(
                  imagePath: imagePath,
                  sourceLabel: attachment.sourceLabel,
                  instruction: text,
                );
          }
        }
        _scrollToBottom();
      } finally {
        if (mounted) {
          setState(() {
            if (hasFile) _fileImportBusy = false;
            if (hasImage) _imageBusy = false;
          });
        }
      }
      return;
    }

    if (_shouldStartSmartUpload(text)) {
      _controller.clear();
      await _pickSmartUploadForPiki();
      return;
    }

    final beforeIds = ref
        .read(pikiMessagesProvider)
        .map((message) => message.id)
        .toSet();
    _controller.clear();
    await ref.read(pikiMessagesProvider.notifier).sendMessage(text);
    _scrollToBottom();
    if (speakResponse) {
      await _speakLatestAgentReply(beforeIds);
    }
  }

  Future<void> _sendPromptFromUi(String prompt) async {
    if (_shouldStartSmartUpload(prompt)) {
      await _pickSmartUploadForPiki();
    } else {
      await ref.read(pikiMessagesProvider.notifier).sendMessage(prompt);
    }
    _scrollToBottom();
  }

  bool _shouldStartSmartUpload(String text) {
    final lower = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return lower.contains('smart upload') ||
        lower.contains('upload to piki') ||
        lower.contains('upload file') ||
        lower.contains('import') ||
        lower.contains('upload') ||
        lower.contains('excel') ||
        lower.contains('spreadsheet') ||
        lower.contains('pdf') ||
        lower.contains('docx') ||
        lower.contains('document') ||
        lower.contains('file');
  }

  Future<void> _toggleListening() async {
    if (_voiceBusy) return;
    if (_autoListening) {
      await _stopAutoListening();
      return;
    }
    if (_isListening) {
      setState(() {
        _isListening = false;
        _voiceBusy = true;
      });
      try {
        final text = await SpeechService.stopAndTranscribe();
        if (!mounted) return;
        _controller.text = text;
        if (_shouldSendVoiceText(text)) {
          await _sendInternal(speakResponse: true);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppErrorMessage.withContext(
                  error,
                  prefix: 'Piki voice failed.',
                  fallback: AppErrorMessage.pikiFailed,
                ),
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _voiceBusy = false);
        }
      }
    } else {
      setState(() => _isListening = true);
      final started = await SpeechService.startRecording();
      if (!started && mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission or recorder is unavailable.'),
          ),
        );
      }
    }
  }

  void _handleAttachmentAction(_PikiAttachmentAction action) {
    switch (action) {
      case _PikiAttachmentAction.cameraPhoto:
        unawaited(_pickImageForPiki(ImageSource.camera));
        break;
      case _PikiAttachmentAction.galleryPhoto:
        unawaited(_pickImageForPiki(ImageSource.gallery));
        break;
      case _PikiAttachmentAction.smartUpload:
        unawaited(_pickSmartUploadForPiki());
        break;
    }
  }

  Future<void> _pickImageForPiki(ImageSource source) async {
    if (_imageBusy) return;
    setState(() => _imageBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (picked == null) return;
      final sizeBytes = await picked.length();
      if (!mounted) return;
      setState(() {
        _pendingAttachments
          ..clear()
          ..add(
            _PikiPendingAttachment.image(
              imagePath: picked.path,
              fileName: picked.name,
              sourceLabel: source == ImageSource.camera ? 'camera' : 'gallery',
              sizeBytes: sizeBytes,
            ),
          );
      });
      _focusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              error,
              prefix: 'Piki image scan failed.',
              fallback: AppErrorMessage.pikiFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _imageBusy = false);
      }
    }
  }

  Future<void> _pickSmartUploadForPiki() async {
    if (_fileImportBusy) return;
    setState(() => _fileImportBusy = true);
    try {
      final file = await SpreadsheetImportReader.pickRows(
        dialogTitle: 'Upload File to Piki',
        allowedExtensions: SpreadsheetImportReader.documentImportExtensions,
      );
      if (file == null) return;
      if (!mounted) return;
      setState(() {
        _pendingAttachments
          ..clear()
          ..add(_PikiPendingAttachment.file(file));
      });
      _focusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              error,
              prefix: 'Piki file import failed.',
              fallback: AppErrorMessage.pikiFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _fileImportBusy = false);
      }
    }
  }

  Future<bool> _confirmSmartImportPlan(PikiSmartImportDraft draft) {
    if (!mounted) return Future.value(false);
    switch (draft.target) {
      case PikiSmartImportTarget.products:
        return _confirmProductImportPlan(draft.plan);
      case PikiSmartImportTarget.sales:
        return _confirmSalesImportPlan(draft.plan);
      case PikiSmartImportTarget.customers:
        return showSmartImportPreviewDialog(
          context,
          plan: draft.plan,
          title: 'Piki Smart Upload: Customers',
          actionLabel: 'Import Customers',
          minimumRequirements: const ['Customers only need a name column.'],
          optionalColumns: const ['phone', 'email'],
          defaultsNote:
              'Piki classified this file as customers. Existing customers are matched by phone, email, or name when available.',
        );
      case PikiSmartImportTarget.expenses:
        return showSmartImportPreviewDialog(
          context,
          plan: draft.plan,
          title: 'Piki Smart Upload: Expenses',
          actionLabel: 'Import Expenses',
          minimumRequirements: const [
            'Expenses need title and amount columns.',
          ],
          optionalColumns: const ['date', 'category', 'note'],
          defaultsNote:
              'Piki classified this file as expenses. Missing dates use today, and new categories are created automatically.',
        );
    }
  }

  Future<bool> _confirmProductImportPlan(SpreadsheetImportPlan plan) {
    if (!mounted) return Future.value(false);
    return showSmartImportPreviewDialog(
      context,
      plan: plan,
      title: 'Piki Smart Upload: Products',
      actionLabel: 'Import Products',
      minimumRequirements: const [
        'New products only need a name column.',
        'Existing products can be updated with sku, barcode, or product_id.',
        'Variants can use parent_product_name plus variant_name.',
      ],
      optionalColumns: const [
        'variant_name',
        'parent_product_name',
        'price',
        'cost',
        'category',
        'stock',
        'low_stock',
        'unit',
        'brand',
        'image_url',
        'description',
        'image_urls',
        'show_online',
        'is_featured',
      ],
      defaultsNote:
          'Excel, CSV, PDF, DOCX, TXT, and JSON files are supported. Blank optional fields are allowed. Missing price and stock import as 0; low stock defaults to 5 and unit defaults to pcs. Piki will attach clear sizes, colors, flavors, and packs as variants instead of duplicate products.',
    );
  }

  Future<bool> _confirmSalesImportPlan(SpreadsheetImportPlan plan) {
    if (!mounted) return Future.value(false);
    return showSmartImportPreviewDialog(
      context,
      plan: plan,
      title: 'Piki Smart Upload: Sales',
      actionLabel: 'Import Sales',
      minimumRequirements: const [
        'Summary sales can use just a total column.',
        'Product sales can use product_name, sku, barcode, product_id, or variant_id.',
        'Service sales can use service_name or service_id.',
      ],
      optionalColumns: const [
        'date',
        'quantity',
        'unit_price',
        'payment_type',
        'customer_name',
        'due_date',
        'reference',
        'tax',
        'discount',
        'note',
      ],
      defaultsNote:
          'Excel, CSV, PDF, DOCX, TXT, and JSON files are supported. Blank optional fields are allowed. Quantity defaults to 1, payment defaults to cash, and item price can come from the product/service.',
    );
  }

  Future<void> _toggleAutoListening() async {
    if (_autoListening) {
      await _stopAutoListening();
      return;
    }
    final token = ++_autoListenToken;
    setState(() => _autoListening = true);
    unawaited(_startAutoListenLoopWhenReady(token));
  }

  Future<void> _startAutoListenLoopWhenReady(int token) async {
    while (_autoLoopRunning && mounted && token == _autoListenToken) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || !_autoListening || token != _autoListenToken) return;
    await _runAutoListenLoop(token);
  }

  Future<void> _stopAutoListening({bool stopPlayback = true}) async {
    _autoListenToken++;
    if (mounted) {
      setState(() {
        _autoListening = false;
        _isListening = false;
        _voiceBusy = false;
      });
    }
    await SpeechService.stopListening();
    if (stopPlayback) {
      await SpeechService.stopPlayback();
    }
  }

  Future<void> _runAutoListenLoop(int token) async {
    if (_autoLoopRunning) return;
    _autoLoopRunning = true;
    try {
      while (mounted && _autoListening && token == _autoListenToken) {
        setState(() {
          _isListening = true;
          _voiceBusy = false;
        });

        final started = await SpeechService.startRecording();
        if (!started) {
          if (mounted) {
            setState(() {
              _autoListening = false;
              _isListening = false;
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

        await Future<void>.delayed(_autoListenWindow);
        if (!mounted || !_autoListening || token != _autoListenToken) {
          await SpeechService.stopListening();
          break;
        }

        setState(() {
          _isListening = false;
          _voiceBusy = true;
        });

        try {
          final text = await SpeechService.stopAndTranscribe();
          if (!mounted || !_autoListening || token != _autoListenToken) {
            break;
          }
          if (_isAutoStopCommand(text)) {
            await SpeechService.speak('Auto listen is off.');
            await _stopAutoListening(stopPlayback: false);
            break;
          }
          if (_shouldSendVoiceText(text)) {
            _controller.text = text;
            await _sendInternal(speakResponse: true);
          }
        } catch (error) {
          if (mounted && _autoListening && token == _autoListenToken) {
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
          if (mounted && token == _autoListenToken) {
            setState(() => _voiceBusy = false);
          }
        }

        await Future<void>.delayed(_autoListenRestartDelay);
      }
    } finally {
      _autoLoopRunning = false;
      if (mounted && token == _autoListenToken) {
        setState(() {
          _autoListening = false;
          _isListening = false;
          _voiceBusy = false;
        });
      }
    }
  }

  bool _shouldSendVoiceText(String text) {
    final normalized = text.trim();
    if (normalized.length < 2) return false;
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .isNotEmpty;
  }

  bool _isAutoStopCommand(String text) {
    final normalized = text.toLowerCase().trim().replaceAll(
      RegExp(r'[^\w\s]'),
      '',
    );
    return normalized == 'stop listening' ||
        normalized == 'piki stop listening' ||
        normalized == 'pause listening' ||
        normalized == 'piki pause listening' ||
        normalized == 'auto listen off' ||
        normalized == 'turn off auto listen' ||
        normalized == 'stop auto listen';
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

  void _showInsightDetails(BuildContext context, dynamic data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppColors.primary),
                  SizedBox(width: 12),
                  Text(
                    'AI Insight Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: 16),
              ...data.details
                  .map<Widget>(
                    (detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              detail,
                              style: TextStyle(fontSize: 14, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ],
          ),
        ),
      ),
    );
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
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: isMobile
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () {
                  AppShell.scaffoldKey.currentState?.openDrawer();
                },
              )
            : null,
        automaticallyImplyLeading: false,
        title: isMobile
            ? _AiIndicator(status: status, compact: true)
            : Text('AI Agent'),
        actions: [
          if (!isMobile) _AiIndicator(status: status),
          Builder(
            builder: (context) {
              return IconButton(
                icon: Icon(Icons.history_rounded),
                tooltip: 'Chat History',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              );
            },
          ),
          SizedBox(width: 8),
        ],
      ),
      endDrawer: const _ChatHistoryDrawer(),
      body: TrainingAnchor(
        id: 'piki.workspace',
        child: Column(
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
                          unawaited(_sendPromptFromUi(prompt));
                        },
                      ),
                    ),
            ),

            // ── Insight / Cart bar ────────────────────────────────────
            if (mode == PikiMode.sell && cart.isNotEmpty)
              _SellCartBar(
                cart: cart,
                onCheckout: () {
                  ref
                      .read(pikiMessagesProvider.notifier)
                      .sendMessage('checkout');
                },
              )
            else if (insight != null &&
                insight.text.isNotEmpty &&
                mode != PikiMode.sell)
              _InsightBar(
                insight: insight.text,
                onTap: () {
                  if (insight.details.isNotEmpty) {
                    _showInsightDetails(context, insight);
                  } else {
                    _scrollToBottom();
                  }
                },
              ),

            // ── Quick actions ───────────────────────────────────────
            _QuickActions(
              actions: mode == PikiMode.sell
                  ? _sellQuickActions
                  : _quickActions,
              onTap: (prompt) {
                unawaited(_sendPromptFromUi(prompt));
              },
            ),

            // ── Mode toggle + input bar ──────────────────────────────
            _BottomBar(
              controller: _controller,
              focusNode: _focusNode,
              mode: mode,
              isListening: _isListening || _voiceBusy,
              isAttachmentBusy: _imageBusy || _fileImportBusy,
              isAutoListening: _autoListening,
              attachments: _pendingAttachments,
              onRemoveAttachment: (index) {
                setState(() => _pendingAttachments.removeAt(index));
              },
              onSend: _send,
              onMicTap: _toggleListening,
              onAttachmentAction: _handleAttachmentAction,
              onAutoListenTap: _toggleAutoListening,
              onSelectMode: (m) =>
                  ref.read(pikiModeProvider.notifier).state = m,
            ),
          ],
        ),
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
                      ? [Color(0xFF00C896), Color(0xFF00A8FF)]
                      : mode == PikiMode.advice
                      ? [Color(0xFF9C27B0), Color(0xFF651FFF)]
                      : [AppColors.primary, Color(0xFFFF7E67)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color:
                        (mode == PikiMode.sell
                                ? Color(0xFF00C896)
                                : mode == PikiMode.advice
                                ? Color(0xFF9C27B0)
                                : AppColors.primary)
                            .withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      mode == PikiMode.sell
                          ? Icons.point_of_sale_rounded
                          : mode == PikiMode.advice
                          ? Icons.lightbulb_rounded
                          : Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 24),
            Text(
              mode == PikiMode.sell
                  ? 'Sell Mode'
                  : mode == PikiMode.advice
                  ? 'Business Coach'
                  : 'Piki AI Assistant',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 8),
            Text(
              mode == PikiMode.sell
                  ? 'Say what to sell — e.g. "2 Fanta"\nThen say "checkout" to go to POS.'
                  : mode == PikiMode.advice
                  ? 'Ask me for strategic advice,\ninsights, or ways to improve profit.'
                  : 'AI can analyze, plan, and complete\ntasks for your business.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            SizedBox(height: 24),
            if (mode != PikiMode.sell && mode != PikiMode.advice)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      (mode == PikiMode.plan
                              ? Theme.of(context).colorScheme.secondary
                              : AppColors.warning)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color:
                        (mode == PikiMode.plan
                                ? Theme.of(context).colorScheme.secondary
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
                          ? Theme.of(context).colorScheme.secondary
                          : AppColors.warning,
                    ),
                    SizedBox(width: 6),
                    Text(
                      mode == PikiMode.plan ? 'Plan Mode' : 'Fast Mode',
                      style: TextStyle(
                        color: mode == PikiMode.plan
                            ? Theme.of(context).colorScheme.secondary
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
        color = Theme.of(context).colorScheme.secondary;
        label = 'Working';
        icon = Icons.auto_awesome;
      case AgentStatus.completed:
        color = AppColors.success;
        label = 'Done';
        icon = Icons.check_circle;
      case AgentStatus.idle:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
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
          SizedBox(width: 6),
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
  final bool compact;

  const _AiIndicator({required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final aiEnabled = OpenRouterService.isEnabled;
    final modelName = OpenRouterService.modelName;
    final shortModel = modelName.contains('/')
        ? modelName.split('/').last
        : modelName;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = compact
        ? math.max(screenWidth - 140.0, 180.0)
        : math.min(screenWidth * 0.55, 360.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: status),
          SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: aiEnabled
                    ? Color(0xFF6B4EE6).withValues(alpha: 0.12)
                    : context.appSurfaceHighlight,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: aiEnabled
                      ? Color(0xFF6B4EE6).withValues(alpha: 0.35)
                      : context.appBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    aiEnabled ? Icons.auto_awesome_rounded : Icons.offline_bolt,
                    size: 14,
                    color: aiEnabled
                        ? Color(0xFF8B6CFF)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      aiEnabled
                          ? 'AI ${shortModel.toUpperCase()}'
                          : 'Local Only',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: aiEnabled
                            ? Color(0xFF8B6CFF)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Insight bar ────────────────────────────────────────────────────────────

class _InsightBar extends StatelessWidget {
  final String insight;
  final VoidCallback? onTap;

  const _InsightBar({required this.insight, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ).createShader(bounds),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Insight:',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    insight,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'View Details',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
              ],
            ),
          ),
        ),
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
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            avatar: Icon(
              action['icon'] as IconData,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(
              action['label'] as String,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            side: BorderSide(color: Theme.of(context).colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
  final bool isListening;
  final bool isAttachmentBusy;
  final bool isAutoListening;
  final List<_PikiPendingAttachment> attachments;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onMicTap;
  final ValueChanged<_PikiAttachmentAction> onAttachmentAction;
  final VoidCallback onAutoListenTap;
  final ValueChanged<PikiMode> onSelectMode;

  const _BottomBar({
    required this.controller,
    required this.focusNode,
    required this.mode,
    required this.isListening,
    required this.isAttachmentBusy,
    required this.isAutoListening,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onMicTap,
    required this.onAttachmentAction,
    required this.onAutoListenTap,
    required this.onSelectMode,
  });

  IconData _getModeIcon(PikiMode m) {
    switch (m) {
      case PikiMode.plan:
        return Icons.route_rounded;
      case PikiMode.fast:
        return Icons.bolt_rounded;
      case PikiMode.sell:
        return Icons.point_of_sale_rounded;
      case PikiMode.advice:
        return Icons.lightbulb_rounded;
    }
  }

  Color _getModeColor(BuildContext context, PikiMode m) {
    switch (m) {
      case PikiMode.plan:
        return Theme.of(context).colorScheme.secondary;
      case PikiMode.fast:
        return AppColors.warning;
      case PikiMode.sell:
        return Color(0xFF00C896);
      case PikiMode.advice:
        return Color(0xFF9C27B0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode toggle row (Desktop/Tablet only)
            if (!isMobile) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ModeToggle(
                      label: 'Plan',
                      icon: Icons.route_rounded,
                      isActive: mode == PikiMode.plan,
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () => onSelectMode(PikiMode.plan),
                    ),
                    SizedBox(width: 8),
                    _ModeToggle(
                      label: 'Fast',
                      icon: Icons.bolt_rounded,
                      isActive: mode == PikiMode.fast,
                      color: AppColors.warning,
                      onTap: () => onSelectMode(PikiMode.fast),
                    ),
                    SizedBox(width: 8),
                    _ModeToggle(
                      label: 'Sell',
                      icon: Icons.point_of_sale_rounded,
                      isActive: mode == PikiMode.sell,
                      color: Color(0xFF00C896),
                      onTap: () => onSelectMode(PikiMode.sell),
                    ),
                    SizedBox(width: 8),
                    _ModeToggle(
                      label: 'Advice',
                      icon: Icons.lightbulb_rounded,
                      isActive: mode == PikiMode.advice,
                      color: Color(0xFF9C27B0),
                      onTap: () => onSelectMode(PikiMode.advice),
                    ),
                    SizedBox(width: 8),
                    Tooltip(
                      message: isAutoListening
                          ? 'Stop auto listen'
                          : 'Start auto listen',
                      child: _ModeToggle(
                        label: 'Auto',
                        icon: isAutoListening
                            ? Icons.hearing_rounded
                            : Icons.hearing_outlined,
                        isActive: isAutoListening,
                        color: AppColors.primary,
                        onTap: onAutoListenTap,
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      isAutoListening
                          ? 'Auto-listening'
                          : mode == PikiMode.plan
                          ? 'Plans step-by-step'
                          : mode == PikiMode.fast
                          ? 'Instant results'
                          : mode == PikiMode.advice
                          ? 'Business Coach'
                          : 'Voice-to-cart POS',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10),
            ],
            if (attachments.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < attachments.length; index += 1)
                      _PendingAttachmentChip(
                        attachment: attachments[index],
                        onRemove: () => onRemoveAttachment(index),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 8),
            ],
            // Input row
            Row(
              children: [
                if (isMobile) ...[
                  PopupMenuButton<PikiMode>(
                    icon: Icon(
                      _getModeIcon(mode),
                      color: _getModeColor(context, mode),
                      size: 24,
                    ),
                    tooltip: 'Switch Mode',
                    onSelected: onSelectMode,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: PikiMode.plan,
                        child: Row(
                          children: [
                            Icon(
                              Icons.route_rounded,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 18,
                            ),
                            SizedBox(width: 12),
                            Text('Plan Mode', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: PikiMode.fast,
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: AppColors.warning,
                              size: 18,
                            ),
                            SizedBox(width: 12),
                            Text('Fast Mode', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: PikiMode.sell,
                        child: Row(
                          children: [
                            Icon(
                              Icons.point_of_sale_rounded,
                              color: Color(0xFF00C896),
                              size: 18,
                            ),
                            SizedBox(width: 12),
                            Text('Sell Mode', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: PikiMode.advice,
                        child: Row(
                          children: [
                            Icon(
                              Icons.lightbulb_rounded,
                              color: Color(0xFF9C27B0),
                              size: 18,
                            ),
                            SizedBox(width: 12),
                            Text('Advice Mode', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value:
                            mode, // Keep value to avoid type errors but trigger toggle via onTap
                        onTap: onAutoListenTap,
                        child: Row(
                          children: [
                            Icon(
                              isAutoListening
                                  ? Icons.hearing_rounded
                                  : Icons.hearing_outlined,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            SizedBox(width: 12),
                            Text(
                              isAutoListening
                                  ? 'Stop Auto Listen'
                                  : 'Start Auto Listen',
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 4),
                ],
                _AttachmentButton(
                  isBusy: isAttachmentBusy,
                  onSelected: onAttachmentAction,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: mode == PikiMode.sell
                          ? 'Say "2 Fanta" or "checkout"...'
                          : mode == PikiMode.advice
                          ? 'Ask for business advice...'
                          : 'Ask Piki AI...',
                      hintStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isListening
                              ? Icons.stop_circle_rounded
                              : Icons.mic_rounded,
                          color: isListening
                              ? AppColors.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: onMicTap,
                      ),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
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
                    icon: Icon(
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

class _PendingAttachmentChip extends StatelessWidget {
  final _PikiPendingAttachment attachment;
  final VoidCallback onRemove;

  const _PendingAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = attachment.kind == _PikiPendingAttachmentKind.file
        ? Icons.description_outlined
        : Icons.image_outlined;
    final size = attachment.sizeLabel;
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  size.isEmpty
                      ? attachment.typeLabel
                      : '${attachment.typeLabel} • $size',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  final bool isBusy;
  final ValueChanged<_PikiAttachmentAction> onSelected;

  const _AttachmentButton({required this.isBusy, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PikiAttachmentAction>(
      tooltip: 'Attach photo or import file',
      enabled: !isBusy,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _PikiAttachmentAction.cameraPhoto,
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 18),
              SizedBox(width: 12),
              Text('Take photo'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _PikiAttachmentAction.galleryPhoto,
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined, size: 18),
              SizedBox(width: 12),
              Text('Choose photo'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _PikiAttachmentAction.smartUpload,
          child: Row(
            children: [
              Icon(Icons.upload_file_outlined, size: 18),
              SizedBox(width: 12),
              Text('Smart upload file'),
            ],
          ),
        ),
      ],
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: isBusy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.attach_file_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
            color: isActive ? color.withValues(alpha: 0.4) : context.appBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? color
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? color
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
      decoration: BoxDecoration(
        color: Color(0xFF003D2B),
        border: Border(top: BorderSide(color: Color(0xFF00C896), width: 1.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Color(0xFF00C896).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_cart_rounded,
                  size: 14,
                  color: Color(0xFF00C896),
                ),
                SizedBox(width: 6),
                Text(
                  '$countStr item${itemCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Color(0xFF00C896),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Total: $currency${total.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onCheckout,
            icon: Icon(Icons.point_of_sale_rounded, size: 16),
            label: Text('Checkout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF00C896),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
              textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHistoryDrawer extends ConsumerWidget {
  const _ChatHistoryDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(pikiSessionsProvider);
    final activeId = ref.watch(pikiActiveSessionIdProvider);

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: AppColors.primary),
                  SizedBox(width: 12),
                  Text(
                    'Chat History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  ref.read(pikiActiveSessionIdProvider.notifier).state = null;
                  Navigator.pop(context);
                },
                icon: Icon(Icons.add_rounded),
                label: Text('New Chat'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Divider(),
            Expanded(
              child: sessionsAsync.when(
                loading: () => Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    AppErrorMessage.from(
                      e,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                  ),
                ),
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return Center(
                      child: Text(
                        'No past chats yet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = session.id == activeId;
                      return ListTile(
                        leading: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 20,
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isActive ? AppColors.primary : null,
                          ),
                        ),
                        subtitle: Text(
                          '${session.updatedAt.day}/${session.updatedAt.month}/${session.updatedAt.year}',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: isActive,
                        selectedTileColor: AppColors.primary.withValues(
                          alpha: 0.05,
                        ),
                        onTap: () {
                          ref.read(pikiActiveSessionIdProvider.notifier).state =
                              session.id;
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
