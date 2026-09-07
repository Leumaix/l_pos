import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/invite_staff_screen.dart';
import '../features/auth/presentation/web_login_screen.dart';
import '../features/business/presentation/settings_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/sell/presentation/payment_screen.dart';
import '../features/sell/presentation/receipt_screen.dart';
import '../features/sell/presentation/sell_screen.dart';
import '../features/shift/application/shift_providers.dart';
import '../features/shift/presentation/close_day_screen.dart';
import '../features/shift/presentation/open_day_screen.dart';
import '../features/stock/presentation/manage_catalog_screen.dart';
import '../features/stock/presentation/manage_category_products_screen.dart';
import '../features/stock/presentation/restock_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import 'app_shell.dart';
import 'go_router_refresh_stream.dart';

/// The web/PWA build's router — deliberately a separate provider from
/// routerProvider (app_router.dart), not a parameterized version of it,
/// so the mobile app's router is never at risk of being changed by this
/// branch's work. Every route below except /login is copied verbatim
/// from app_router.dart: same screens, same redirect rules, same
/// owner-only/shift-gating logic — none of that is auth-scheme-specific.
/// Two differences: /login points at WebLoginScreen (plain email-link,
/// no PIN) instead of LoginScreen, and /verify-email doesn't exist at
/// all — that route is for a second staff member verifying on a SHARED
/// device without disturbing the first person's active session, which
/// has no equivalent when every staff member has their own browser
/// session. Home's "Verify another staff member" menu item is hidden
/// accordingly (see HomeScreen.showStaffHandoffOption).
final webRouterProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final shiftRepository = ref.watch(shiftRepositoryProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: Listenable.merge([
      GoRouterRefreshStream(authRepository.authStateChanges()),
      GoRouterRefreshStream(shiftRepository.watchCurrentShift()),
    ]),
    redirect: (context, state) {
      final signedIn = authRepository.currentUser != null;
      final onLogin = state.matchedLocation == '/login';

      if (!signedIn && !onLogin) return '/login';
      if (signedIn && onLogin) return '/home';

      final isOwner = authRepository.currentUser?.role == 'owner';
      final onOwnerOnlyRoute =
          state.matchedLocation.startsWith('/stock') || state.matchedLocation.startsWith('/reports');
      if (signedIn && !isOwner && onOwnerOnlyRoute) return '/home';

      final onSellRoute = state.matchedLocation.startsWith('/sell');
      if (signedIn && onSellRoute && shiftRepository.currentShift == null) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const WebLoginScreen()),
      GoRoute(path: '/invite-staff', builder: (context, state) => const InviteStaffScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/open-day', builder: (context, state) => OpenDayScreen(onOpened: () => context.go('/home'))),
      GoRoute(path: '/close-day', builder: (context, state) => CloseDayScreen(onClosed: () => context.go('/home'))),
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
                  showStaffHandoffOption: false,
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
