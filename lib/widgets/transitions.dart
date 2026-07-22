import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';

class SlideFadeTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final Offset beginOffset;
  final Curve curve;

  const SlideFadeTransition({
    super.key,
    required this.animation,
    required this.child,
    this.beginOffset = const Offset(0.1, 0),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: curve)),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}

class ScaleFadeTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double beginScale;
  final Curve curve;

  const ScaleFadeTransition({
    super.key,
    required this.animation,
    required this.child,
    this.beginScale = 0.95,
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: beginScale, end: 1.0).animate(
        CurvedAnimation(parent: animation, curve: curve),
      ),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}

class SlideUpTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final Curve curve;

  const SlideUpTransition({
    super.key,
    required this.animation,
    required this.child,
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: curve)),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}

Route<T> createSlideRoute<T>({
  required WidgetBuilder builder,
  Duration duration = AppConstants.animationNormal,
  Offset beginOffset = const Offset(0.1, 0),
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideFadeTransition(
        animation: animation,
        beginOffset: beginOffset,
        child: child,
      );
    },
    transitionDuration: duration,
    reverseTransitionDuration: duration,
  );
}

Route<T> createScaleRoute<T>({
  required WidgetBuilder builder,
  Duration duration = AppConstants.animationNormal,
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return ScaleFadeTransition(
        animation: animation,
        child: child,
      );
    },
    transitionDuration: duration,
    reverseTransitionDuration: duration,
  );
}

Route<T> createSlideUpRoute<T>({
  required WidgetBuilder builder,
  Duration duration = AppConstants.animationNormal,
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideUpTransition(
        animation: animation,
        child: child,
      );
    },
    transitionDuration: duration,
    reverseTransitionDuration: duration,
  );
}

Route<T> createModalRoute<T>({
  required WidgetBuilder builder,
  Duration duration = AppConstants.animationNormal,
  Color barrierColor = const Color(0x80000000),
  bool barrierDismissible = true,
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      
      return SlideUpTransition(
        animation: curvedAnimation,
        child: child,
      );
    },
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    opaque: false,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
  );
}

extension NavigatorAnimationExtension on NavigatorState {
  Future<T?> pushSlide<T extends Object?>(
    WidgetBuilder builder, {
    Duration duration = AppConstants.animationNormal,
    Offset beginOffset = const Offset(0.1, 0),
  }) {
    return push<T>(
      createSlideRoute<T>(
        builder: builder,
        duration: duration,
        beginOffset: beginOffset,
      ),
    );
  }

  Future<T?> pushScale<T extends Object?>(
    WidgetBuilder builder, {
    Duration duration = AppConstants.animationNormal,
  }) {
    return push<T>(
      createScaleRoute<T>(builder: builder, duration: duration),
    );
  }

  Future<T?> pushSlideUp<T extends Object?>(
    WidgetBuilder builder, {
    Duration duration = AppConstants.animationNormal,
  }) {
    return push<T>(
      createSlideUpRoute<T>(builder: builder, duration: duration),
    );
  }
}
