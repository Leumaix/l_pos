import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:leumadepos/features/sell/application/last_sale_provider.dart';
import 'package:leumadepos/features/sell/domain/cart_line.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';
import 'package:leumadepos/features/sell/presentation/receipt_screen.dart';

/// Proves both of ReceiptScreen's Share paths — the Web Share API being
/// available (most mobile browsers, and native platforms) versus not
/// (most desktop browsers, where share_plus's own web implementation
/// throws rather than degrading gracefully) — without ever touching a
/// real platform channel. Neither path is reachable through share_plus's
/// own public API (it exposes no canShare() check to app code — only
/// its internal web plugin does), so ReceiptScreen takes an injectable
/// ShareText seam instead, real Share.share by default.
void main() {
  final sale = Sale(
    id: 'sale-1',
    receiptNumber: '0001',
    items: const [
      GasCartLine(id: 'line-1', mode: GasSaleMode.kg, kg: 5, unitsDeducted: 7000, oversells: false),
    ],
    subtotal: 7000,
    total: 7000,
    payments: const [
      PaymentLine(method: PaymentMethod.cash, amountNaira: 10000),
      PaymentLine(method: PaymentMethod.cash, amountNaira: -3000),
    ],
    staffId: 'staff-1',
    staffName: 'Amaka',
    createdAt: DateTime(2026, 9, 6, 10),
  );

  Widget widgetWithSale(ShareText shareText) {
    return ProviderScope(
      overrides: [lastSaleProvider.overrideWith((ref) => sale)],
      child: MaterialApp(
        home: ReceiptScreen(onNewSale: () {}, shareText: shareText),
      ),
    );
  }

  testWidgets('when the Web Share API is available, sharing succeeds and no clipboard fallback happens', (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    var shareCalled = false;
    String? sharedText;
    Future<ShareResult> fakeShare(String text, {String? subject}) async {
      shareCalled = true;
      sharedText = text;
      return const ShareResult('ok', ShareResultStatus.success);
    }

    await tester.pumpWidget(widgetWithSale(fakeShare));
    await tester.ensureVisible(find.text('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(shareCalled, isTrue);
    expect(sharedText, contains('0001'));
    expect(clipboardText, isNull); // the fallback never ran
    expect(find.text('Sharing isn\'t available here — receipt copied to clipboard instead.'), findsNothing);
  });

  testWidgets(
    'when the Web Share API is unavailable (share_plus throws, e.g. most desktop browsers), '
    'falls back to copying the receipt to the clipboard and tells the staff member',
    (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      Future<ShareResult> throwingShare(String text, {String? subject}) async {
        throw Exception('Navigator.canShare() is unavailable');
      }

      await tester.pumpWidget(widgetWithSale(throwingShare));
      await tester.ensureVisible(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('0001')); // the actual receipt text, not a placeholder
      expect(find.text('Sharing isn\'t available here — receipt copied to clipboard instead.'), findsOneWidget);
    },
  );
}
