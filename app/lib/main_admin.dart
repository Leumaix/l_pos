// The super-admin onboarding tool's entry point — a separate build target
// from the mobile POS app (lib/main.dart), same idea as
// lib/main_debug_landscape.dart having its own entry point rather than a
// flag inside the real app. Run locally with:
//   flutter run -d chrome -t lib/main_admin.dart
//
// Every repository provider this pulls in (adminAuthRepositoryProvider,
// businessOnboardingRepositoryProvider) already defaults to its real
// Firebase-backed implementation — see application/*_controller.dart —
// so no provider overrides are needed here, same as lib/main.dart itself.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Per this whole feature's explicit build constraint: never touch the
  // live lpos-ac40b project until Sammy confirms Monday's launch is done
  // and stable. Debug builds (flutter run, no --release) point at the
  // local Firestore/Auth emulator suite instead — a release build of
  // this same entry point would skip this and hit the real project, for
  // whenever that eventually becomes the deliberate choice, not a
  // leftover to remember to remove.
  if (kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8090);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }

  runApp(const ProviderScope(child: AdminApp()));
}
