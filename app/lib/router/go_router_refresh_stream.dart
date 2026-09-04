import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a Stream (here, auth state changes) into a Listenable so
/// go_router's `refreshListenable` re-evaluates redirects whenever the
/// stream emits — the standard go_router + Riverpod stream recipe.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
