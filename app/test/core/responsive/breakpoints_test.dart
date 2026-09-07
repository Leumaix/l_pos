import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/responsive/breakpoints.dart';

void main() {
  void useSurface(
    WidgetTester tester,
    Size physicalSize,
    double devicePixelRatio,
  ) {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Breakpoints.isDesktop', () {
    testWidgets(
      'is false at the tablet reference width (the real Itel tablet landscape size used '
      'throughout the existing wide-mode tests, ~853 logical px)',
      (tester) async {
        // Same real dimensions as sell_screen_wide_test.dart /
        // keypad_entry_layout_test.dart's "wide" case.
        useSurface(tester, const Size(1280, 800), 1.5);

        late bool isDesktop;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isDesktop = Breakpoints.isDesktop(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isDesktop, isFalse);
      },
    );

    testWidgets('is true at exactly 1024 logical px, the desktop threshold', (
      tester,
    ) async {
      useSurface(tester, const Size(1024, 768), 1.0);

      late bool isDesktop;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isDesktop = Breakpoints.isDesktop(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDesktop, isTrue);
    });

    testWidgets(
      'is true comfortably above 1024, e.g. a real 1440x900 laptop window',
      (tester) async {
        useSurface(tester, const Size(1440, 900), 1.0);

        late bool isDesktop;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isDesktop = Breakpoints.isDesktop(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isDesktop, isTrue);
      },
    );
  });

  group('ResponsiveCenter with desktopMaxWidth', () {
    Widget harness() => const MaterialApp(
      home: Scaffold(
        body: ResponsiveCenter(
          maxWidth: 400,
          desktopMaxWidth: 800,
          child: SizedBox(),
        ),
      ),
    );

    double renderedMaxWidth(WidgetTester tester) {
      final box = tester.widget<ConstrainedBox>(
        find.byKey(const ValueKey('responsiveCenterConstraint')),
      );
      return box.constraints.maxWidth;
    }

    testWidgets(
      'uses maxWidth (not desktopMaxWidth) below the desktop breakpoint, even '
      'though desktopMaxWidth is set',
      (tester) async {
        useSurface(
          tester,
          const Size(1280, 800),
          1.5,
        ); // tablet reference, ~853 logical
        await tester.pumpWidget(harness());

        expect(renderedMaxWidth(tester), 400);
      },
    );

    testWidgets('switches to desktopMaxWidth at/above the desktop breakpoint', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 900), 1.0);
      await tester.pumpWidget(harness());

      expect(renderedMaxWidth(tester), 800);
    });

    testWidgets('omitting desktopMaxWidth changes nothing at any width — stays on maxWidth even '
        'at desktop widths', (tester) async {
      useSurface(tester, const Size(1440, 900), 1.0);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveCenter(maxWidth: 400, child: SizedBox()),
          ),
        ),
      );

      expect(renderedMaxWidth(tester), 400);
    });
  });
}
