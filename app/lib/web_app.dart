import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/web_auth_controller.dart';
import 'router/web_app_router.dart';

/// The web/PWA build's root widget — same idea as AdminApp: a small,
/// separate composition that reuses the real feature screens/providers
/// underneath, with its own auth front door. Unlike the mobile app's
/// LeumadeposApp, this never touches app_links — on web, an email-link
/// sign-in completes by the browser reopening this exact page with the
/// link's parameters in the URL, checked once here at startup, same as
/// AdminApp.
class WebApp extends ConsumerStatefulWidget {
  const WebApp({super.key});

  @override
  ConsumerState<WebApp> createState() => _WebAppState();
}

class _WebAppState extends ConsumerState<WebApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webAuthControllerProvider.notifier).completeSignInIfLinkPresent(Uri.base.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(webRouterProvider);
    return MaterialApp.router(
      title: 'Leumadepos',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
