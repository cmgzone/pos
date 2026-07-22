import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width >= AppConstants.desktopBreakpoint && desktop != null) {
          return desktop!;
        } else if (width >= AppConstants.tabletBreakpoint && tablet != null) {
          return tablet!;
        } else if (width >= AppConstants.mobileBreakpoint && tablet != null) {
          return tablet!;
        } else {
          return mobile;
        }
      },
    );
  }
}

class ResponsiveVisibility extends StatelessWidget {
  final Widget child;
  final bool showOnMobile;
  final bool showOnTablet;
  final bool showOnDesktop;

  const ResponsiveVisibility({
    super.key,
    required this.child,
    this.showOnMobile = true,
    this.showOnTablet = true,
    this.showOnDesktop = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < AppConstants.mobileBreakpoint;
    final isTablet = width >= AppConstants.mobileBreakpoint &&
        width < AppConstants.desktopBreakpoint;
    final isDesktop = width >= AppConstants.desktopBreakpoint;

    if (isMobile && !showOnMobile) return const SizedBox.shrink();
    if (isTablet && !showOnTablet) return const SizedBox.shrink();
    if (isDesktop && !showOnDesktop) return const SizedBox.shrink();

    return child;
  }
}

extension ResponsiveExtension on BuildContext {
  bool get isMobile => MediaQuery.sizeOf(this).width < AppConstants.mobileBreakpoint;
  bool get isTablet {
    final width = MediaQuery.sizeOf(this).width;
    return width >= AppConstants.mobileBreakpoint &&
        width < AppConstants.desktopBreakpoint;
  }
  bool get isDesktop => MediaQuery.sizeOf(this).width >= AppConstants.desktopBreakpoint;

  T responsive<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop && desktop != null) return desktop;
    if (isTablet && tablet != null) return tablet;
    return mobile;
  }
}
