import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin wrapper over `connectivity_plus` that exposes a boolean stream of
/// "does this device *think* it has a network path".
///
/// A `true` value here is not a guarantee of end-to-end reachability — the
/// radio may be up while the internet is broken — but a `false` value is a
/// strong signal that outbound requests will fail. We use it to *trigger*
/// drain attempts on offline → online transitions; the drainer itself is
/// the authority on whether requests actually succeed and will re-park work
/// in the outbox if they don't.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// One-shot check: `true` iff the device currently reports any transport
  /// other than [ConnectivityResult.none].
  Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    return _isOnline(results);
  }

  /// Emits `true` when the device transitions to any non-none transport and
  /// `false` when it goes fully offline. Duplicates are suppressed so
  /// callers only see actual state changes.
  Stream<bool> onStatusChanged() {
    return _connectivity.onConnectivityChanged.map(_isOnline).distinct();
  }

  static bool _isOnline(List<ConnectivityResult> results) {
    // The list is documented never-empty; `none` is only present when it is
    // the sole element.
    return !(results.length == 1 && results.first == ConnectivityResult.none);
  }
}

/// Singleton Riverpod handle for [ConnectivityService].
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Reactive online/offline flag. `null` while the first probe is in flight,
/// `true`/`false` thereafter. Screens can `.watch` this for a banner or
/// pending-count pill (Phase 4b).
final connectivityStatusProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  // Emit the current state first so consumers don't wait for a change event.
  yield await service.isConnected();
  yield* service.onStatusChanged();
});
