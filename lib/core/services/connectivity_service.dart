import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityServiceProvider =
    AsyncNotifierProvider<ConnectivityService, bool>(ConnectivityService.new);

class ConnectivityService extends AsyncNotifier<bool> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;

  @override
  FutureOr<bool> build() async {
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final isOnline = result != ConnectivityResult.none;
      state = AsyncValue.data(isOnline);
    });

    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  bool get isOnline => state.valueOrNull ?? false;

  void dispose() {
    _subscription?.cancel();
  }
}
