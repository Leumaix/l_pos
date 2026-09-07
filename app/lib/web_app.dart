import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'router/web_app_router.dart';

/// The web/PWA build's root widget — same idea as AdminApp: a small,
/// separate composition that reuses the real feature screens/providers
/// underneath, with its own auth front door. Email+password sign-up/login
/// (see WebAuthController) needs no startup URL inspection the way the
/// earlier email-link version did — WebAuthController's own constructor
/// already resumes the right screen from Firebase's persisted session
/// (signed in, mid-verification, or neither) on its own.
class WebApp extends ConsumerWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(webRouterProvider);
    return MaterialApp.router(
      title: 'Leumadepos',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
