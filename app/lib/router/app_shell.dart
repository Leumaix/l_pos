import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_bottom_nav.dart';
import '../features/auth/application/auth_providers.dart';

/// The bottom-nav shell: Home, Sell, Customers, and — owner only — Stock
/// and Reports. Branch order/indices always stay Home,Sell,Customers,
/// Stock,Reports regardless of role (StatefulNavigationShell's branches
/// are fixed at router-construction time); what changes per role is only
/// which of those branch indices get a visible tab here. The real block
/// on an attendant reaching /stock or /reports some other way (a stale
/// deep link, back button) is the router's own redirect, not this list.
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final GoRouterState state;

  const AppShell({super.key, required this.navigationShell, required this.state});

  static const _allItems = [
    NavTabItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    NavTabItem(
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale,
      label: 'Sell',
    ),
    NavTabItem(
      icon: Icons.people_alt_outlined,
      activeIcon: Icons.people_alt,
      label: 'Customers',
    ),
    NavTabItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Stock',
    ),
    NavTabItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Reports'),
  ];
  static const _ownerOnlyBranchIndices = {3, 4}; // Stock, Reports

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hide the tab bar on a pushed sub-route (e.g. /sell/payment,
    // /sell/receipt) rather than just a tab root (e.g. /sell). Those
    // sub-flows are meant to be focused — and on a phone-height screen a
    // numpad's bottom row sits close enough to the tab bar that a stray
    // tap can silently switch tabs mid-payment.
    final segments = state.uri.pathSegments;
    final onSubRoute = segments.length > 1;

    // .select, not a plain .watch: AppUser has no == override, so every
    // authStateChanges() emission — including harmless, redundant ones
    // (a token refresh, a repeated _controller.add with the same user)
    // — is a "new" value by identity, forcing a full rebuild here on
    // every single one. That rebuild recreates AppBottomNav's item list
    // from scratch; combined with that list having no widget Keys (see
    // app_bottom_nav.dart), a rebuild landing mid-gesture could leave a
    // stale tap in Flutter's gesture arena resolving against the wrong
    // widget — this is what caused a real, reproduced bug where tapping
    // Home's account icon also fired the bottom nav's Home-tab handler.
    // Selecting just the owner boolean means this only rebuilds when
    // that actually flips, not on every emission.
    final isOwner = ref.watch(authStateProvider.select((s) => s.valueOrNull?.role == 'owner'));
    final visibleBranchIndices = [
      for (var i = 0; i < _allItems.length; i++)
        if (isOwner || !_ownerOnlyBranchIndices.contains(i)) i,
    ];
    final items = [for (final i in visibleBranchIndices) _allItems[i]];
    final currentVisibleIndex = visibleBranchIndices.indexOf(navigationShell.currentIndex);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: onSubRoute
          ? null
          : AppBottomNav(
              // Falls back to Home's tab (always index 0, always visible)
              // if the current branch isn't in this role's visible set —
              // the router's redirect already sends an attendant away
              // from Stock/Reports before this could otherwise show none
              // selected.
              currentIndex: currentVisibleIndex < 0 ? 0 : currentVisibleIndex,
              items: items,
              onTap: (tappedIndex) {
                final branchIndex = visibleBranchIndices[tappedIndex];
                navigationShell.goBranch(
                  branchIndex,
                  initialLocation: branchIndex == navigationShell.currentIndex,
                );
              },
            ),
    );
  }
}
