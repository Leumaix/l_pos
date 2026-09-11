import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/gifts/domain/gift.dart';

void main() {
  final createdAt = DateTime(2026, 9, 15, 14, 0);

  Gift build({
    GiftItemType itemType = GiftItemType.gas,
    String? productId,
    num quantity = 1,
    int estimatedValueNaira = 1400,
    String reason = 'Sample for a new customer',
    String shiftId = 'hist-1',
    bool requiresApproval = false,
    String? approvedByOwnerUid,
  }) {
    return buildGift(
      itemType: itemType,
      productId: productId,
      quantity: quantity,
      estimatedValueNaira: estimatedValueNaira,
      reason: reason,
      staffId: 'staff-1',
      staffName: 'Ifeoma',
      id: 'gift-1',
      shiftId: shiftId,
      requiresApproval: requiresApproval,
      approvedByOwnerUid: approvedByOwnerUid,
      createdAt: createdAt,
    );
  }

  group('quantity validation', () {
    test('zero quantity throws InvalidGiftQuantityException', () {
      expect(() => build(quantity: 0), throwsA(isA<InvalidGiftQuantityException>()));
    });

    test('negative quantity throws InvalidGiftQuantityException', () {
      expect(() => build(quantity: -1), throwsA(isA<InvalidGiftQuantityException>()));
    });

    test('a positive quantity succeeds', () {
      expect(build(quantity: 2.5).quantity, 2.5);
    });
  });

  group('reason is always required', () {
    test('throws GiftReasonRequiredException with no reason', () {
      expect(() => build(reason: ''), throwsA(isA<GiftReasonRequiredException>()));
    });

    test('throws GiftReasonRequiredException with a blank/whitespace-only reason', () {
      expect(() => build(reason: '   '), throwsA(isA<GiftReasonRequiredException>()));
    });

    test('succeeds with a real reason', () {
      expect(build(reason: 'Goodwill gesture').reason, 'Goodwill gesture');
    });
  });

  group('a product gift requires productId', () {
    test('throws ProductRequiredForGiftException with no productId', () {
      expect(
        () => build(itemType: GiftItemType.product, productId: null),
        throwsA(isA<ProductRequiredForGiftException>()),
      );
    });

    test('succeeds with a productId, carried onto the record', () {
      final gift = build(itemType: GiftItemType.product, productId: 'cyl-6kg');
      expect(gift.productId, 'cyl-6kg');
    });

    test('a gas gift needs no productId at all', () {
      expect(build(itemType: GiftItemType.gas, productId: null).productId, isNull);
    });
  });

  test('constructs the full record on the happy path, including approval fields', () {
    final gift = build(
      itemType: GiftItemType.product,
      productId: 'acc-hose',
      quantity: 3,
      estimatedValueNaira: 2400,
      requiresApproval: true,
      approvedByOwnerUid: 'owner-uid-1',
    );
    expect(gift.id, 'gift-1');
    expect(gift.itemType, GiftItemType.product);
    expect(gift.productId, 'acc-hose');
    expect(gift.quantity, 3);
    expect(gift.estimatedValueNaira, 2400);
    expect(gift.staffId, 'staff-1');
    expect(gift.staffName, 'Ifeoma');
    expect(gift.shiftId, 'hist-1');
    expect(gift.requiresApproval, isTrue);
    expect(gift.approvedByOwnerUid, 'owner-uid-1');
    expect(gift.createdAt, createdAt);
  });
}
