import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/admin/application/admin_auth_controller.dart';
import 'features/admin/presentation/admin_login_screen.dart';
import 'features/admin/presentation/admin_onboard_screen.dart';

/// The super-admin onboarding tool — a separate, small app from
/// LeumadeposApp (the mobile POS), not a screen bolted onto it. Two
/// routes, no shift-gating, no role split, no shared-device handoff
/// concerns: one person, one browser.
class AdminApp extends ConsumerStatefulWidget {
  const AdminApp({super.key});

  @override
  ConsumerState<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends ConsumerState<AdminApp> {
  @override
  void initState() {
    super.initState();
    // On web, an email-link sign-in completes by the browser reopening
    // this exact page with the link's parameters in the URL — no
    // app_links package, no OS-level deep-link registration, none of the
    // Android App Links machinery the mobile app needs. Checked once,
    // here, rather than on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adminAuthControllerProvider.notifier).completeSignInIfLinkPresent(Uri.base.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(_adminRouterProvider);
    return MaterialApp.router(
      title: 'Leumadepos Admin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}

final _adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _AdminAuthRefreshListenable(ref),
    redirect: (context, state) {
      final signedIn = ref.read(adminAuthControllerProvider).stage == AdminAuthStage.done;
      final onLogin = state.matchedLocation == '/login';
      if (!signedIn && !onLogin) return '/login';
      if (signedIn && onLogin) return '/onboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const AdminLoginScreen()),
      GoRoute(path: '/onboard', builder: (context, state) => const AdminOnboardScreen()),
    ],
  );
});

/// Re-evaluates the redirect above whenever sign-in state changes — same
/// need as the mobile app's GoRouterRefreshStream, but simpler: this just
/// listens to the one Riverpod controller directly rather than wrapping
/// a repository stream, since there's no separate "shift changed on
/// another device" concern here to also watch.
class _AdminAuthRefreshListenable extends ChangeNotifier {
  _AdminAuthRefreshListenable(this._ref) {
    _subscription = _ref.listen<AdminAuthState>(
      adminAuthControllerProvider,
      (previous, next) {
        if (previous?.stage != next.stage) notifyListeners();
      },
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AdminAuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
