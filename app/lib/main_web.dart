// The web/PWA build's entry point — a separate build target from the
// mobile POS app (lib/main.dart) and the admin tool (lib/main_admin.dart),
// same "new entry point, not a flag inside an existing one" convention
// both of those already established. Run locally with:
//   flutter run -d chrome -t lib/main_web.dart
//
// Points at leumadepos-web-dev (firebase_options_web_dev.dart) —
// deliberately NOT firebase_options.dart, which is the real mobile app's
// config for the live lpos-ac40b project. This whole feature branch
// exists to build and test the web/PWA experience against a project
// that isn't tomorrow's real onboarding, so unlike main_admin.dart
// (which points at local emulators specifically to avoid the live
// project during dev), this points directly at leumadepos-web-dev for
// real — that project itself already IS the sandbox.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/application/auth_providers.dart';
import 'features/auth/application/web_auth_controller.dart';
import 'firebase_options_web_dev.dart';
import 'web_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Same reasoning and same ports as main_admin.dart's own kDebugMode
  // branch: auth bugs are much faster and safer to iterate on against a
  // local, disposable emulator than against leumadepos-web-dev — seed
  // whatever broken account state you need to reproduce, break it as
  // many times as you like, nothing real is at risk. A debug run
  // (flutter run, no --release) never touches the real sandbox project;
  // a release build of this same entry point is unaffected and still
  // points straight at it, exactly as before.
  if (kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8090);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }

  await _enableWebPersistence();

  runApp(
    ProviderScope(
      overrides: [
        // Every Firebase-backed repository downstream (invites, stock,
        // customers, sales, shift, business, checkout) reads
        // authRepositoryProvider's activeFirestore — pointing it at the
        // same WebAuthRepository instance webAuthControllerProvider uses
        // is what makes the real feature screens work unmodified under
        // this simplified auth scheme. See auth_repository.dart's own
        // doc comment on activeFirestore.
        authRepositoryProvider.overrideWith((ref) => ref.watch(webAuthRepositoryProvider)),
      ],
      child: const WebApp(),
    ),
  );
}

/// Turns on IndexedDB-backed Firestore persistence for web — without
/// this, cloud_firestore's web SDK caches in memory only (confirmed
/// directly from the installed cloud_firestore_web 4.4.12 plugin's own
/// source: unlike mobile, where persistence defaults ON, web defaults
/// to `memoryLocalCache()` unless told otherwise), meaning Home/Stock/
/// Reports show nothing at all on a reload until the network catches up
/// — with this on, they show their last-known data immediately instead.
/// Doesn't touch correctness: the money/inventory-critical writes
/// (changeGasRate, checkout, shift open/close) already go through
/// runTransaction(), which needs a live connection regardless of any
/// local-cache setting.
///
/// A shop keeping this open in two browser tabs at once is a real
/// scenario worth getting right, not a hypothetical — so this
/// deliberately does NOT use the modern, non-deprecated
/// `Settings(persistenceEnabled: true)` API. Checked directly in the
/// installed plugin's source (cloud_firestore_web 4.4.12): that path
/// builds `persistentLocalCache()` with no tabManager argument at all,
/// which makes the underlying JS SDK default to
/// `persistentSingleTabManager()` — and a *second* tab under that
/// manager doesn't fail quietly, it rejects with a real
/// `failed-precondition` error the first time that tab touches
/// Firestore (confirmed against the JS SDK's own documented behavior,
/// not assumed) — which would surface in this app as a wrong, confusing
/// message (e.g. sign-in failing with "that link is invalid or
/// expired", when the real cause is a persistence lock held by another
/// tab). The web-only, now-deprecated `enablePersistence(
/// PersistenceSettings(synchronizeTabs: true))` is, in this exact
/// installed plugin version, the only path that actually configures
/// multiple tabs to share one synchronized cache instead of one tab
/// winning and the rest failing — deprecated only means "a newer API
/// shape exists," not "broken now." Revisit this once the package is
/// upgraded far enough for `Settings.persistenceEnabled` to expose a
/// tabManager option directly (the JS interop bindings for it already
/// exist in this plugin, just not wired through Settings yet).
///
/// Never allowed to block or crash startup: wrapped in its own
/// try/catch so an unexpected failure (e.g. IndexedDB unavailable in
/// some private-browsing modes) just leaves Firestore on its default
/// memory-only cache for that session rather than taking the whole app
/// down before it even renders.
Future<void> _enableWebPersistence() async {
  if (!kIsWeb) return;
  try {
    // ignore: deprecated_member_use
    await FirebaseFirestore.instance.enablePersistence(
      // ignore: deprecated_member_use
      const PersistenceSettings(synchronizeTabs: true),
    );
  } catch (e) {
    debugPrint('_enableWebPersistence: could not enable persistence, continuing memory-only — $e');
  }
}
