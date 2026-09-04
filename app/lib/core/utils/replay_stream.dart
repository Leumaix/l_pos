import 'dart:async';

/// Wraps a broadcast [updates] stream so every new listener immediately
/// gets the current value (from [current]), then subsequent updates — the
/// same semantics as Firebase's realtime listeners (and how
/// FakeAuthRepository.authStateChanges behaves). A plain broadcast stream
/// doesn't replay past events to a late subscriber; this fixes that for
/// the various fake repositories backing screens before Firestore exists.
Stream<T> replayLatest<T>(T Function() current, Stream<T> updates) {
  return Stream.multi((controller) {
    controller.add(current());
    final subscription = updates.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });
}
