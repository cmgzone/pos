import 'package:flutter/widgets.dart';

class AppNavigator {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static NavigatorState? get state => navigatorKey.currentState;
  static BuildContext? get context => navigatorKey.currentContext;
}
