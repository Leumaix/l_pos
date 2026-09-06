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
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/application/auth_providers.dart';
import 'features/auth/application/web_auth_controller.dart';
import 'firebase_options_web_dev.dart';
import 'web_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
