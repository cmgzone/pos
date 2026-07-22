import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  static const _key = 'app_theme_mode';
  bool _userSetMode = false;

  ThemeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null) return;
    final mode = ThemeMode.values.cast<ThemeMode?>().firstWhere(
      (e) => e?.name == saved,
      orElse: () => null,
    );
    if (mode != null && !_userSetMode && mounted) {
      state = mode;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    _userSetMode = true;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.system) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, mode.name);
    }
  }
}
