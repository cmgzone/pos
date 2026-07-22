import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_colors.dart';

/// A full-screen camera barcode scanner overlay
class BarcodeScannerScreen extends StatefulWidget {
  final bool allowQr;
  final String title;

  const BarcodeScannerScreen({
    super.key,
    this.allowQr = false,
    this.title = 'Scan Barcode',
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      // Only detect 1D product barcode formats — excludes QR codes, URLs, etc.
      formats: [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.itf,
        BarcodeFormat.codabar,
        if (widget.allowQr) BarcodeFormat.qrCode,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;

      // Guard: reject URL-encoded content (QR codes that slip through)
      final lower = raw.toLowerCase();
      if (lower.startsWith('http') ||
          lower.startsWith('www.') ||
          lower.contains('://')) {
        continue;
      }

      // Guard: product barcodes are alphanumeric (EAN/UPC/Code128 etc.)
      // reject strings with spaces or non-barcode chars
      final looksLikeBarcode =
          RegExp(r'^[A-Za-z0-9\-\.\s]{4,}$').hasMatch(raw.trim()) &&
          !raw.contains('  '); // double space = not a barcode
      if (!looksLikeBarcode) continue;

      _hasScanned = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(raw.trim());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: state.torchState == TorchState.on
                      ? AppColors.warning
                      : Colors.white,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Scan overlay
          _ScanOverlay(),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanArea = constraints.maxWidth * 0.7;
        final top = (constraints.maxHeight - scanArea) / 2;
        final left = (constraints.maxWidth - scanArea) / 2;

        return Stack(
          children: [
            // Dimmed background
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: scanArea,
                      height: scanArea,
                      decoration: BoxDecoration(
                        color: Colors.red, // any color works with srcOut
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Corner borders
            Positioned(
              top: top,
              left: left,
              child: _CornerBorder(
                size: 40,
                borderColor: AppColors.primary,
                position: _CornerPosition.topLeft,
              ),
            ),
            Positioned(
              top: top,
              right: left,
              child: _CornerBorder(
                size: 40,
                borderColor: AppColors.primary,
                position: _CornerPosition.topRight,
              ),
            ),
            Positioned(
              bottom: top,
              left: left,
              child: _CornerBorder(
                size: 40,
                borderColor: AppColors.primary,
                position: _CornerPosition.bottomLeft,
              ),
            ),
            Positioned(
              bottom: top,
              right: left,
              child: _CornerBorder(
                size: 40,
                borderColor: AppColors.primary,
                position: _CornerPosition.bottomRight,
              ),
            ),
            // Instructions
            Positioned(
              bottom: top - 60,
              left: 0,
              right: 0,
              child: const Text(
                'Point your camera at a barcode',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _CornerPosition { topLeft, topRight, bottomLeft, bottomRight }

class _CornerBorder extends StatelessWidget {
  final double size;
  final Color borderColor;
  final _CornerPosition position;

  const _CornerBorder({
    required this.size,
    required this.borderColor,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border(
          top:
              position == _CornerPosition.topLeft ||
                  position == _CornerPosition.topRight
              ? BorderSide(color: borderColor, width: 4)
              : BorderSide.none,
          left:
              position == _CornerPosition.topLeft ||
                  position == _CornerPosition.bottomLeft
              ? BorderSide(color: borderColor, width: 4)
              : BorderSide.none,
          right:
              position == _CornerPosition.topRight ||
                  position == _CornerPosition.bottomRight
              ? BorderSide(color: borderColor, width: 4)
              : BorderSide.none,
          bottom:
              position == _CornerPosition.bottomLeft ||
                  position == _CornerPosition.bottomRight
              ? BorderSide(color: borderColor, width: 4)
              : BorderSide.none,
        ),
      ),
    );
  }
}

/// Mixin to handle hardware barcode scanner input (USB/Bluetooth scanners that emulate keyboard)
/// These scanners typically type characters very fast and end with Enter key.
mixin HardwareScannerMixin<T extends StatefulWidget> on State<T> {
  final StringBuffer _scanBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.now();

  /// Override this to handle scanned barcode
  void onBarcodeScanned(String barcode);

  FocusNode? _scannerFocusNode;

  /// Call this in your build method to wrap your widget with the key listener
  Widget wrapWithScanner({required Widget child}) {
    // Only use hardware scanner on desktop platforms
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return child;
    }

    _scannerFocusNode ??= FocusNode();
    return KeyboardListener(
      focusNode: _scannerFocusNode!,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }

  void disposeScannerFocusNode() {
    _scannerFocusNode?.dispose();
    _scannerFocusNode = null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final now = DateTime.now();
    final timeDiff = now.difference(_lastKeyTime).inMilliseconds;

    // Hardware scanners burst characters in < 50 ms gaps.
    // 80 ms is still generous but rejects fast human typing (100–150 ms/key).
    if (timeDiff > 80) {
      _scanBuffer.clear();
    }

    _lastKeyTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final code = _scanBuffer.toString().trim();
      _scanBuffer.clear();

      if (code.length < 4) return; // too short

      // Reject URL-like strings produced by keyboard wedge scanning a QR
      final lower = code.toLowerCase();
      if (lower.startsWith('http') ||
          lower.startsWith('www.') ||
          lower.contains('://')) {
        return;
      }

      // Must look like a real barcode (alphanumeric, no surrounding whitespace blocks)
      final looksLikeBarcode = RegExp(r'^[A-Za-z0-9\-\.]+$').hasMatch(code);
      if (!looksLikeBarcode) return;

      onBarcodeScanned(code);
    } else {
      final char = event.character;
      if (char != null && char.isNotEmpty) {
        _scanBuffer.write(char);
      }
    }
  }
}
