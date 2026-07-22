import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';

class AnimatedModal extends StatelessWidget {
  final Widget child;
  final Color? barrierColor;
  final bool barrierDismissible;
  final Duration duration;

  const AnimatedModal({
    super.key,
    required this.child,
    this.barrierColor,
    this.barrierDismissible = true,
    this.duration = AppConstants.animationNormal,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: child,
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? barrierColor,
    bool barrierDismissible = true,
    Duration duration = AppConstants.animationNormal,
  }) {
    return showGeneralDialog<T>(
      context: context,
      pageBuilder: (context, animation, secondaryAnimation) {
        return builder(context);
      },
      barrierColor: barrierColor ?? Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: duration,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideUpModal(animation: animation, child: child);
      },
    );
  }
}

class SlideUpModal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const SlideUpModal({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class ScaleInModal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const ScaleInModal({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        ),
      ),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}

class FadeInModal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const FadeInModal({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: child,
    );
  }
}

class BottomSheetAnimation extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const BottomSheetAnimation({
    super.key,
    required this.child,
    this.duration = AppConstants.animationNormal,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedModal(
      duration: duration,
      child: child,
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? backgroundColor,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    Color? barrierColor,
    Duration duration = AppConstants.animationNormal,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      barrierColor: barrierColor,
    );
  }
}

class AnimatedDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final IconData? icon;
  final Color? iconColor;

  const AnimatedDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 32),
              const SizedBox(height: 16),
            ],
            DefaultTextStyle(
              style: theme.textTheme.headlineSmall!,
              child: title,
            ),
            const SizedBox(height: 12),
            DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: content,
            ),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Duration duration = AppConstants.animationNormal,
  }) {
    return showGeneralDialog<T>(
      context: context,
      pageBuilder: (context, animation, secondaryAnimation) {
        return builder(context);
      },
      barrierColor: Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: duration,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleInModal(animation: animation, child: child);
      },
    );
  }
}

class AnimatedSnackbar extends StatelessWidget {
  final String message;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final Duration duration;

  const AnimatedSnackbar({
    super.key,
    required this.message,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.duration = AppConstants.animationNormal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      color: backgroundColor ?? theme.colorScheme.inverseSurface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor ?? theme.colorScheme.onInverseSurface, size: 20),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor ?? theme.colorScheme.onInverseSurface,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void show({
    required BuildContext context,
    required String message,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    Duration duration = const Duration(seconds: 3),
    Duration animationDuration = AppConstants.animationNormal,
  }) {
    final snackbar = SnackBar(
      content: AnimatedSnackbar(
        message: message,
        icon: icon,
        backgroundColor: backgroundColor,
        textColor: textColor,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      margin: const EdgeInsets.all(16),
      padding: EdgeInsets.zero,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackbar);
  }
}
