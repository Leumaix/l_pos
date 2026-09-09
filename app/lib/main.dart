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
  //
  // automaticHostMapping: false — both plugins otherwise unconditionally
  // rewrite 'localhost' to '10.0.2.2' on ANY Android target (see
  // cloud_firestore's firestore.dart / firebase_auth's firebase_auth.dart),
  // which is only correct for an Android Virtual Device. On a real phone,
  // 10.0.2.2 isn't the host machine — it silently breaks the adb reverse
  // tunnels above, which forward the device's own literal localhost, not
  // 10.0.2.2. Confirmed live on a real device (TECNO KI5q): without this
  // flag the app was quietly trying to reach 10.0.2.2, never the tunnel.
  if (kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator(
      'localhost',
      8090,
      automaticHostMapping: false,
    );
    await FirebaseAuth.instance.useAuthEmulator(
      'localhost',
      9099,
      automaticHostMapping: false,
    );
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
