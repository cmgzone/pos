import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';

class StaggeredListAnimation extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration duration;
  final Duration staggerDelay;
  final Curve curve;

  const StaggeredListAnimation({
    super.key,
    required this.index,
    required this.child,
    this.duration = AppConstants.animationNormal,
    this.staggerDelay = const Duration(milliseconds: 50),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        final opacity = value;
        final translateY = (1.0 - value) * 20.0;
        
        return Transform.translate(
          offset: Offset(0, translateY),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class StaggeredGridAnimation extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  const StaggeredGridAnimation({
    super.key,
    required this.index,
    required this.child,
    this.duration = AppConstants.animationNormal,
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<StaggeredGridAnimation> createState() => _StaggeredGridAnimationState();
}

class _StaggeredGridAnimationState extends State<StaggeredGridAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  late Animation<double> _translateY;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _scale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _translateY = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _translateY.value),
          child: Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class AnimatedList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final Duration staggerDelay;
  final Duration itemDuration;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  const AnimatedList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.staggerDelay = const Duration(milliseconds: 50),
    this.itemDuration = AppConstants.animationNormal,
    this.controller,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: items.length,
      itemBuilder: (context, index) {
        return StaggeredListAnimation(
          index: index,
          staggerDelay: staggerDelay,
          duration: itemDuration,
          child: itemBuilder(context, items[index], index),
        );
      },
    );
  }
}

class AnimatedGrid<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final Duration staggerDelay;
  final Duration itemDuration;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  const AnimatedGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.crossAxisCount = 2,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.childAspectRatio = 1.0,
    this.staggerDelay = const Duration(milliseconds: 50),
    this.itemDuration = AppConstants.animationNormal,
    this.controller,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final row = index ~/ crossAxisCount;
        final col = index % crossAxisCount;
        final delay = Duration(
          milliseconds: (row * crossAxisCount + col) * staggerDelay.inMilliseconds,
        );

        return StaggeredGridAnimation(
          index: index,
          delay: delay,
          duration: itemDuration,
          child: itemBuilder(context, items[index], index),
        );
      },
    );
  }
}

class AnimatedVisibility extends StatefulWidget {
  final Widget child;
  final bool visible;
  final Duration duration;
  final Curve curve;

  const AnimatedVisibility({
    super.key,
    required this.child,
    this.visible = true,
    this.duration = AppConstants.animationNormal,
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<AnimatedVisibility> createState() => _AnimatedVisibilityState();
}

class _AnimatedVisibilityState extends State<AnimatedVisibility>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _translateY;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _translateY = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void didUpdateWidget(AnimatedVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _translateY.value),
          child: Opacity(
            opacity: _opacity.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
