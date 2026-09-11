import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/gifts/application/gift_controller.dart';
import 'package:leumadepos/features/gifts/application/gift_providers.dart';
import 'package:leumadepos/features/gifts/data/gift_repository.dart';
import 'package:leumadepos/features/gifts/domain/gift.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

const _testStaff = AppUser(
  uid: 'staff-1',
  name: 'Ifeoma',
  email: 'ifeoma@leumadepos.test',
  role: 'attendant',
);

void main() {
  late FakeShiftRepository shift;
  late FakeInventoryRepository inventory;
  late FakeGiftRepository gifts;
  late FakeAuthRepository auth;
  late ProviderContainer container;

  Future<ProviderContainer> buildContainer({bool openShift = true}) async {
    shift = FakeShiftRepository(openShift: openShift);
    inventory = FakeInventoryRepository();
    gifts = FakeGiftRepository(inventory: inventory, shift: shift);
    auth = FakeAuthRepository();
    final c = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_testStaff)),
        authRepositoryProvider.overrideWithValue(auth),
        shiftRepositoryProvider.overrideWithValue(shift),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        giftRepositoryProvider.overrideWithValue(gifts),
      ],
    );
    await c.read(authStateProvider.future);
    return c;
  }

  tearDown(() => container.dispose());

  test('a gas gift under the threshold (2kg) commits without any owner approval', () async {
    container = await buildContainer();

    final gift = await container.read(giftControllerProvider).recordGift(
      itemType: GiftItemType.gas,
      quantity: 1.5,
      reason: 'Sample for a regular customer',
    );

    expect(gift.requiresApproval, isFalse);
    expect(gift.approvedByOwnerUid, isNull);
    expect(gifts.debugGifts, hasLength(1));
    // 1.5kg at the fake's seeded rate (1400/kg) = 2100 units deducted.
    expect(inventory.currentGasStock.units, 63000 - 2100);
  });

  test('a product gift under the threshold (₦2000) commits without any owner approval', () async {
    container = await buildContainer();
    final before = inventory.currentProducts.firstWhere((p) => p.id == 'acc-hose').stockCount;

    final gift = await container.read(giftControllerProvider).recordGift(
      itemType: GiftItemType.product,
      productId: 'acc-hose', // price 800
      quantity: 2, // 1600, under threshold
      reason: 'Damaged in handling',
    );

    expect(gift.requiresApproval, isFalse);
    expect(gift.estimatedValueNaira, 1600);
    final after = inventory.currentProducts.firstWhere((p) => p.id == 'acc-hose').stockCount;
    expect(after, before - 2);
  });

  test('a gas gift over the threshold throws OwnerApprovalRequiredException when no owner PIN is supplied', () async {
    container = await buildContainer();

    expect(
      () => container.read(giftControllerProvider).recordGift(
        itemType: GiftItemType.gas,
        quantity: 3, // over kGasGiftApprovalThresholdKg (2)
        reason: 'Large sample',
      ),
      throwsA(isA<OwnerApprovalRequiredException>()),
    );
  });

  test('a gas gift over the threshold commits once the correct owner PIN is supplied', () async {
    container = await buildContainer();

    final gift = await container.read(giftControllerProvider).recordGift(
      itemType: GiftItemType.gas,
      quantity: 3,
      reason: 'Large sample',
      ownerEmail: 'chidi@leumadepos.test', // FakeAuthRepository's seeded owner
      ownerPin: '1234',
    );

    expect(gift.requiresApproval, isTrue);
    expect(gift.approvedByOwnerUid, 'seed-owner');
    expect(gifts.debugGifts, hasLength(1));
    // The active session must stay the attendant's — verifyActiveOwnerPin
    // must never switch it, the whole point of the mechanism.
    expect(container.read(authStateProvider).value?.uid, 'staff-1');
  });

  test('a wrong owner PIN throws InvalidCredentialsException and commits nothing', () async {
    container = await buildContainer();

    expect(
      () => container.read(giftControllerProvider).recordGift(
        itemType: GiftItemType.gas,
        quantity: 3,
        reason: 'Large sample',
        ownerEmail: 'chidi@leumadepos.test',
        ownerPin: '0000',
      ),
      throwsA(isA<InvalidCredentialsException>()),
    );
    expect(gifts.debugGifts, isEmpty);
  });

  test('a correct PIN for a non-owner throws NotAnActiveOwnerException and commits nothing', () async {
    container = await buildContainer();

    expect(
      () => container.read(giftControllerProvider).recordGift(
        itemType: GiftItemType.gas,
        quantity: 3,
        reason: 'Large sample',
        ownerEmail: 'ifeoma@leumadepos.test', // FakeAuthRepository's seeded attendant, not owner
        ownerPin: '1111',
      ),
      throwsA(isA<NotAnActiveOwnerException>()),
    );
    expect(gifts.debugGifts, isEmpty);
  });

  test('a gift with no shift open throws NoShiftOpenException — every gift needs one, unconditionally', () async {
    container = await buildContainer(openShift: false);

    expect(
      () => container.read(giftControllerProvider).recordGift(
        itemType: GiftItemType.gas,
        quantity: 1,
        reason: 'Sample',
      ),
      throwsA(isA<NoShiftOpenException>()),
    );
  });

  test('empty reason throws GiftReasonRequiredException before ever reaching the repository', () async {
    container = await buildContainer();

    expect(
      () => container.read(giftControllerProvider).recordGift(
        itemType: GiftItemType.gas,
        quantity: 1,
        reason: '',
      ),
      throwsA(isA<GiftReasonRequiredException>()),
    );
    expect(gifts.debugGifts, isEmpty);
  });
}
