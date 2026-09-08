import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Same reasoning and same ports as main_admin.dart/main_web.dart's own
  // kDebugMode branches: this is the one entry point that was still
  // missing it — every debug run (flutter run, no --release) on a real
  // device or the mobile-shaped emulator now stays off the real
  // lpos-ac40b project entirely; a release build is unaffected and still
  // points straight at it, exactly as before. On a physical device this
  // needs the local emulator ports reachable at localhost, e.g. via
  // `adb reverse tcp:8090 tcp:8090` and `adb reverse tcp:9099 tcp:9099`.
  if (kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8090);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }

  // Phone stays portrait-primary, but the shop's counter-mounted tablet
  // sits in landscape — allow both and let the OS pick based on the
  // physical device orientation. See the design system's responsive notes.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const ProviderScope(child: LeumadeposApp()));
}
