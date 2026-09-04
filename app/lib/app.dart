import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/verification_controller.dart';
import 'router/app_router.dart';

class LeumadeposApp extends ConsumerStatefulWidget {
  const LeumadeposApp({super.key});

  @override
  ConsumerState<LeumadeposApp> createState() => _LeumadeposAppState();
}

class _LeumadeposAppState extends ConsumerState<LeumadeposApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Covers both a cold start via the link and one arriving while the
    // app is already running — app_links replays the launch URI (if any)
    // as the stream's first event.
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingUri);
  }

  void _handleIncomingUri(Uri uri) {
    final link = uri.toString();
    // A cheap, app-agnostic format check — isSignInWithEmailLink just
    // parses the URL, no network call and no dependency on which staff
    // member's secondary FirebaseApp this ends up being completed
    // against, so the default app instance is fine here.
    if (!fb_auth.FirebaseAuth.instance.isSignInWithEmailLink(link)) return;

    ref.read(routerProvider).go('/verify-email');
    ref.read(verificationControllerProvider.notifier).handleIncomingLink(link);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Leumadepos',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
