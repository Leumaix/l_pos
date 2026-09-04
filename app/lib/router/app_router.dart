import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/invite_staff_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/business/presentation/settings_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/sell/presentation/payment_screen.dart';
import '../features/sell/presentation/receipt_screen.dart';
import '../features/sell/presentation/sell_screen.dart';
import '../features/stock/presentation/manage_catalog_screen.dart';
import '../features/stock/presentation/manage_category_products_screen.dart';
import '../features/stock/presentation/restock_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import 'app_shell.dart';
import 'go_router_refresh_stream.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(authRepository.authStateChanges()),
    redirect: (context, state) {
      final signedIn = authRepository.currentUser != null;
      final onLogin = state.matchedLocation == '/login';
      // Reachable regardless of signedIn — it's how a device BECOMES
      // verified while signed out, but it's also reachable while someone
      // ELSE is already signed in on this shared device (a second staff
      // member completing their own one-time setup mid-shift). Never
      // force-redirected away by the "signedIn -> /home" rule below, or
      // that second case would bounce them to the OTHER person's Home
      // before they can see the "ask them to sign out" message —
      // VerifyEmailScreen navigates to /home itself, only when ITS OWN
      // session actually activates.
      final onVerify = state.matchedLocation == '/verify-email';

      if (!signedIn && !onLogin && !onVerify) return '/login';
      if (signedIn && onLogin) return '/home';

      // Stock and Reports expose business-wide inventory value and sales
      // history — owner-only. Home already leaves their tiles off for an
      // attendant, but that's just UI; this is what actually stops
      // someone reaching either screen directly (a stale deep link, the
      // back button, or the bottom nav bar's own tap index).
      final isOwner = authRepository.currentUser?.role == 'owner';
      final onOwnerOnlyRoute =
          state.matchedLocation.startsWith('/stock') || state.matchedLocation.startsWith('/reports');
      if (signedIn && !isOwner && onOwnerOnlyRoute) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailScreen()),
      // Owner-only in the UI (see Home's account menu), enforced for
      // real by firestore.rules (isActiveOwnerOf) on the actual invite
      // writes — reaching this route some other way just shows an empty
      // list and a failed submit, nothing sensitive.
      GoRoute(path: '/invite-staff', builder: (context, state) => const InviteStaffScreen()),
      // Same owner-only-in-UI, rules-enforced-for-real pattern as
      // /invite-staff — see firestore.rules' scoped update on
      // businesses/{businessId}.settings.gasTankCapacityKg.
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      // Same owner-only-in-UI, rules-enforced-for-real pattern — see
      // firestore.rules' /categories and /products rules.
      GoRoute(
        path: '/manage-catalog',
        builder: (context, state) => const ManageCatalogScreen(),
        routes: [
          GoRoute(
            path: ':categoryId',
            builder: (context, state) => ManageCategoryProductsScreen(
              categoryId: state.pathParameters['categoryId']!,
              categoryName: state.extra as String?,
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell, state: state),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => HomeScreen(
                  onSell: () => context.go('/sell'),
                  onCustomers: () => context.go('/customers'),
                  onStock: () => context.go('/stock'),
                  onReports: () => context.go('/reports'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sell',
                builder: (context, state) => SellScreen(
                  onGoToPayment: () => context.push('/sell/payment'),
                ),
                routes: [
                  GoRoute(
                    path: 'payment',
                    builder: (context, state) => PaymentScreen(
                      onSaleComplete: (sale) => context.pushReplacement('/sell/receipt'),
                      onEmptyCart: () => context.go('/sell'),
                    ),
                  ),
                  GoRoute(
                    path: 'receipt',
                    builder: (context, state) => ReceiptScreen(
                      onNewSale: () => context.go('/sell'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/customers',
                builder: (context, state) => CustomersScreen(
                  onOpenCustomer: (customer) => context.push('/customers/${customer.id}'),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => CustomerDetailScreen(
                      customerId: state.pathParameters['id']!,
                      onStartCreditSale: () => context.go('/sell'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stock',
                builder: (context, state) => StockScreen(
                  onRestock: () => context.push('/stock/restock'),
                ),
                routes: [
                  GoRoute(
                    path: 'restock',
                    builder: (context, state) => const RestockScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
