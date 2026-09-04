import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/auth/data/fake_auth_repository.dart';
import 'features/customers/application/customer_providers.dart';
import 'features/customers/data/customer_repository.dart';
import 'features/sell/application/checkout_providers.dart';
import 'features/sell/application/inventory_providers.dart';
import 'features/sell/application/sales_providers.dart';
import 'features/sell/data/checkout_repository.dart';
import 'features/sell/data/inventory_repository.dart';
import 'features/sell/data/sales_repository.dart';
import 'firebase_options.dart';

/// DEBUG-ONLY entry point — boots straight past real auth into a fully
/// fake-repository-backed owner session, for visually checking layout
/// (e.g. a landscape pass on a tablet) without real Firebase auth or
/// real data. Launch explicitly:
///   flutter run -t lib/main_debug_landscape.dart -d DEVICE_ID
/// Never referenced by the real app entry point or any release build —
/// this file existing changes nothing about lib/main.dart.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final authRepository = FakeAuthRepository();
  // Pre-authenticated before runApp — the router's redirect logic sends
  // an already-signed-in user straight to /home, so this alone is what
  // skips the login screen entirely.
  await authRepository.signInWithEmailAndPin(email: 'chidi@leumadepos.test', pin: '1234');

  final inventory = FakeInventoryRepository();
  final customers = FakeCustomerRepository();
  final sales = FakeSalesRepository();

  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        customerRepositoryProvider.overrideWithValue(customers),
        salesRepositoryProvider.overrideWithValue(sales),
        checkoutRepositoryProvider.overrideWithValue(
          FakeCheckoutRepository(inventory: inventory, customers: customers, sales: sales),
        ),
      ],
      child: const LeumadeposApp(),
    ),
  );
}
