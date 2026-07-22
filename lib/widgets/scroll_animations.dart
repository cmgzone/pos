import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';

class ScrollRevealAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double offset;
  final bool enableOpacity;

  const ScrollRevealAnimation({
    super.key,
    required this.child,
    this.duration = AppConstants.animationNormal,
    this.curve = Curves.easeOutCubic,
    this.offset = 50.0,
    this.enableOpacity = true,
  });

  @override
  State<ScrollRevealAnimation> createState() => _ScrollRevealAnimationState();
}

class _ScrollRevealAnimationState extends State<ScrollRevealAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _translateY;
  bool _hasAnimated = false;

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

    _translateY = Tween<double>(begin: widget.offset, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(bool isVisible) {
    if (isVisible && !_hasAnimated) {
      _hasAnimated = true;
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('scroll_reveal_${widget.child.hashCode}'),
      onVisibilityChanged: (info) {
        _onVisibilityChanged(info.visibleFraction > 0.1);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _translateY.value),
            child: Opacity(
              opacity: widget.enableOpacity ? _opacity.value : 1.0,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class ParallaxScrollEffect extends StatelessWidget {
  final Widget child;
  final double parallaxFactor;

  const ParallaxScrollEffect({
    super.key,
    required this.child,
    this.parallaxFactor = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return Scrollable(
      viewportBuilder: (context, position) {
        return AnimatedBuilder(
          animation: position,
          builder: (context, child) {
            final scrollOffset = position.pixels;
            return Transform.translate(
              offset: Offset(0, -scrollOffset * parallaxFactor),
              child: child,
            );
          },
          child: child,
        );
      },
    );
  }
}

class ScrollProgressIndicator extends StatefulWidget {
  final ScrollController controller;
  final Color color;
  final double height;
  final BorderRadius? borderRadius;

  const ScrollProgressIndicator({
    super.key,
    required this.controller,
    this.color = Colors.blue,
    this.height = 3.0,
    this.borderRadius,
  });

  @override
  State<ScrollProgressIndicator> createState() =>
      _ScrollProgressIndicatorState();
}

class _ScrollProgressIndicatorState extends State<ScrollProgressIndicator> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateProgress);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateProgress);
    super.dispose();
  }

  void _updateProgress() {
    if (!widget.controller.hasClients) return;
    
    final maxScroll = widget.controller.position.maxScrollExtent;
    final currentScroll = widget.controller.position.pixels;
    
    if (maxScroll > 0) {
      setState(() {
        _progress = (currentScroll / maxScroll).clamp(0.0, 1.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppConstants.animationFast,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.2),
        borderRadius: widget.borderRadius ?? BorderRadius.circular(widget.height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: _progress,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: widget.borderRadius ?? BorderRadius.circular(widget.height / 2),
          ),
        ),
      ),
    );
  }
}

class FadeInOnScroll extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;

  const FadeInOnScroll({
    super.key,
    required this.child,
    this.duration = AppConstants.animationNormal,
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollRevealAnimation(
      duration: duration,
      curve: curve,
      offset: 30.0,
      enableOpacity: true,
      child: child,
    );
  }
}

class SlideInOnScroll extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double offset;

  const SlideInOnScroll({
    super.key,
    required this.child,
    this.duration = AppConstants.animationNormal,
    this.curve = Curves.easeOutCubic,
    this.offset = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollRevealAnimation(
      duration: duration,
      curve: curve,
      offset: offset,
      enableOpacity: false,
      child: child,
    );
  }
}

class ScaleInOnScroll extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double beginScale;

  const ScaleInOnScroll({
    super.key,
    required this.child,
    this.duration = AppConstants.animationNormal,
    this.curve = Curves.easeOutCubic,
    this.beginScale = 0.9,
  });

  @override
  State<ScaleInOnScroll> createState() => _ScaleInOnScrollState();
}

class _ScaleInOnScrollState extends State<ScaleInOnScroll>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scale = Tween<double>(begin: widget.beginScale, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(bool isVisible) {
    if (isVisible && !_hasAnimated) {
      _hasAnimated = true;
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('scale_in_${widget.child.hashCode}'),
      onVisibilityChanged: (info) {
        _onVisibilityChanged(info.visibleFraction > 0.1);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class VisibilityDetector extends StatefulWidget {
  final Widget child;
  final void Function(VisibilityInfo info) onVisibilityChanged;

  const VisibilityDetector({
    super.key,
    required this.child,
    required this.onVisibilityChanged,
  });

  @override
  State<VisibilityDetector> createState() => _VisibilityDetectorState();
}

class _VisibilityDetectorState extends State<VisibilityDetector> {
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _checkVisibility();
        return false;
      },
      child: KeyedSubtree(
        key: _key,
        child: widget.child,
      ),
    );
  }

  void _checkVisibility() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;

    final visibleTop = position.dy.clamp(0.0, screenHeight);
    final visibleBottom = (position.dy + size.height).clamp(0.0, screenHeight);
    final visibleHeight = visibleBottom - visibleTop;
    final visibleFraction = visibleHeight / size.height;

    widget.onVisibilityChanged(VisibilityInfo(visibleFraction: visibleFraction));
  }
}

class VisibilityInfo {
  final double visibleFraction;

  const VisibilityInfo({required this.visibleFraction});
}
