import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/ble_controller.dart';
import 'package:cpready/main.dart';
import 'package:cpready/screens/calibration_screen.dart';
import 'package:cpready/screens/live_practice_screen.dart';
import 'package:cpready/screens/root_screens.dart';

Widget _wrap({required BleController controller, required Widget home}) {
  return AppScope(
    controller: controller,
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets('setup requires a trainee name before continuing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        controller: BleController(),
        home: const PracticeSetupScreen(),
      ),
    );

    final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);


    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(continueButton).onPressed,
      isNotNull,
    );

    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Yes (All Good)'), findsOneWidget);
  });

  testWidgets('calibration stays not-ready without a READY packet',
      (WidgetTester tester) async {
    final controller = BleController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        controller: controller,
        home: const CalibrationScreen(traineeName: 'Alice'),
      ),
    );
    await tester.pump();

    expect(
      find.text('Not ready. Keep hands still and release downward pressure.'),
      findsOneWidget,
    );
    final beginButton = find.widgetWithText(ElevatedButton, 'Begin Session');
    expect(find.byWidgetPredicate((w) => w is ElevatedButton), findsWidgets);
    expect(tester.widget<ElevatedButton>(beginButton).onPressed, isNull);
  });

  testWidgets('End Session 3s hold without summary lands on Session Complete',
      (WidgetTester tester) async {
    final controller = BleController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        controller: controller,
        home: const LivePracticeScreen(traineeName: 'Alice'),
      ),
    );
    await tester.pump();

    expect(find.text('Waiting for telemetry\u2026'), findsOneWidget);
    expect(find.text('End Session'), findsOneWidget);

    // Press and hold the End Session circle for the full 3 seconds.
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('End Session')));
    await tester.pump(const Duration(milliseconds: 600)); // long-press armed
    // Label switches to the pressed hint while the hold is active.
    expect(find.text('Hold to End Session'), findsOneWidget);
    expect(find.text('End Session'), findsNothing);
    await tester.pump(const Duration(seconds: 3)); // ring fills
    // AnimationController reports `completed` on the tick strictly after
    // the duration, so nudge the fake clock forward one frame.
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(find.text('Stopping session\u2026'), findsOneWidget);

    // No FINAL_SUMMARY arrives (no ESP32 in tests): 2 s window expires.
    // Bounded pumps instead of pumpAndSettle: the 'Stopping session'
    // indeterminate progress indicator animates forever by design.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Session Complete'), findsOneWidget);
    expect(find.textContaining('Session Not Saved'), findsOneWidget);

    // Manual return pops the result screen (root route in this harness).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Return to Practice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Session Complete'), findsNothing);

    // Unmount to cancel the stale-check timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
