import 'dart:async';

typedef AuthRevalidationCallback = Future<void> Function();

final class AuthRevalidationGate {
  AuthRevalidationGate(this._revalidate);

  final AuthRevalidationCallback _revalidate;
  Future<void>? _inFlight;

  Future<void> request() {
    final current = _inFlight;
    if (current != null) {
      return current;
    }
    final future = _revalidate();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }
}
