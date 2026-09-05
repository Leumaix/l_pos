import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/firebase_shift_repository.dart';
import '../data/shift_repository.dart';

/// Same "one-line swap" pattern as auth/inventory/business: real by
/// default, overridden with FakeShiftRepository in tests.
final shiftRepositoryProvider = Provider<ShiftRepository>(
  (ref) => FirebaseShiftRepository(ref.watch(firebaseAuthRepositoryProvider)),
);

final currentShiftProvider = StreamProvider((ref) => ref.watch(shiftRepositoryProvider).watchCurrentShift());

/// Owner-only at the rules level — Reports' shift history section.
final shiftHistoryProvider = StreamProvider((ref) => ref.watch(shiftRepositoryProvider).watchShiftHistory());
