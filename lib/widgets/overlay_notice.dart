import 'dart:async';

import 'package:flutter/material.dart';

/// Displays short feedback above every route, including an open form dialog.
///
/// A regular [ScaffoldMessenger] belongs to the page beneath a dialog, which
/// means its snack bars can be obscured by the modal route. Dialogs should use
/// this helper for warnings, errors, and confirmations that must remain visible.
class AppOverlayNotice {
  AppOverlayNotice._();

  static OverlayEntry? _entry;
  static Timer? _dismissTimer;

  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
      return;
    }

    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _OverlayNoticeCard(
        snackBar: snackBar,
        onDismiss: () => _remove(entry),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(snackBar.duration, () => _remove(entry));
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    final entry = _entry;
    _entry = null;
    entry?.remove();
  }

  static void _remove(OverlayEntry entry) {
    if (!identical(_entry, entry)) return;
    dismiss();
  }
}

class _OverlayNoticeCard extends StatelessWidget {
  final SnackBar snackBar;
  final VoidCallback onDismiss;

  const _OverlayNoticeCard({required this.snackBar, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snackBarTheme = theme.snackBarTheme;
    final backgroundColor =
        snackBar.backgroundColor ??
        snackBarTheme.backgroundColor ??
        theme.colorScheme.inverseSurface;
    final contentStyle =
        snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onInverseSurface,
        );
    final action = snackBar.action;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, -12 * (1 - value)),
                  child: child,
                ),
              ),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Material(
                  key: const ValueKey('app-overlay-notice'),
                  color: backgroundColor,
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.28),
                  shape:
                      snackBar.shape ??
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding:
                        snackBar.padding ??
                        const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: DefaultTextStyle.merge(
                            style: contentStyle,
                            child: snackBar.content,
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              action.onPressed();
                              onDismiss();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  action.textColor ??
                                  snackBarTheme.actionTextColor ??
                                  theme.colorScheme.inversePrimary,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(action.label),
                          ),
                        ],
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: 'Dismiss message',
                          onPressed: onDismiss,
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color:
                              snackBar.closeIconColor ??
                              snackBarTheme.closeIconColor ??
                              contentStyle?.color,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
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
