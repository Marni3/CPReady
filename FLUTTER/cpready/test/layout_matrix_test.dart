/// Layout regression gate: every screen, at every phone size the app supports,
/// with the system text scale at its lowest, normal and maximum values.
///
/// The app clamps the system text scale (see [AppLayout.maxTextScale]), so the
/// 2.0 case proves the clamp holds rather than proving 2.0 layouts exist.
///
/// A RenderFlex overflow is reported as a test exception, so any screen that
/// cannot fit its content fails the test with the size and scale in the reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cpready/src/config/config.dart';
import 'package:cpready/src/core/app_scope.dart';
import 'package:cpready/src/core/ble/ble_controller.dart';
import 'package:cpready/src/core/history/session_repository.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/begin_compression/begin_compression_screen.dart';
import 'package:cpready/src/screens/calibration/calibration_screen.dart';
import 'package:cpready/src/screens/guide/guide_screen.dart';
import 'package:cpready/src/screens/hand_placement/hand_placement_screen.dart';
import 'package:cpready/src/screens/home/home_screen.dart';
import 'package:cpready/src/screens/live_practice/live_practice_screen.dart';
import 'package:cpready/src/screens/practice/practice_screen.dart';
import 'package:cpready/src/screens/session_complete/session_complete_screen.dart';
import 'package:cpready/src/screens/setup/practice_setup_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/main.dart';

/// Screen sizes the layout must survive, in logical pixels. 320 × 568 is the
/// supported floor; the rest cover current budget and flagship phones.
const List<Size> _sizes = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(393, 873),
  Size(412, 915),
];

/// Text scales to exercise: normal, Android's large setting, and the
/// accessibility maximum (which the app clamps).
const List<double> _scales = <double>[1.0, 1.3, 2.0];

/// Device pixel ratio used for every case; 2.75 matches the reference phone.
const double _pixelRatio = 2.75;

/// System insets of a typical phone, in logical pixels.
const double _topInset = 24;
const double _bottomInset = 16;

/// A database factory that cannot open a database, so screens that read
/// History render their unavailable state instead of needing a real SQLite
/// plugin. Layout is what these tests measure.
class _FailingDatabaseFactory implements DatabaseFactory {
  const _FailingDatabaseFactory();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('History storage is out of scope for layout tests');
  }
}

/// One screen under test, with the arguments each needs to build.
class _Case {
  const _Case(this.name, this.build);

  final String name;
  final Widget Function() build;
}

const CprMetrics _summary = CprMetrics(
  packetType: AppBleConfig.packetFinalSummary,
  recoilComplete: true,
  recoilPercentage: 97,
  rateCpm: 110,
  depthCm: 5.4,
  depthMm: 54,
  ccfPercent: 96,
  audioPromptCode: 0,
  totalCompressions: 152,
  elapsedSeconds: 83,
);

final List<_Case> _cases = <_Case>[
  _Case('MainShell', () => const MainShell()),
  _Case('Home', () => const HomeScreen()),
  _Case('Practice', () => const PracticeScreen()),
  _Case('Guide', () => const GuideScreen()),
  _Case('Setup', () => const PracticeSetupScreen()),
  _Case(
    'HandPlacement',
    () => const HandPlacementScreen(traineeName: 'Alexandra'),
  ),
  _Case('Calibration', () => const CalibrationScreen(traineeName: 'Alexandra')),
  _Case(
    'Countdown',
    () => const BeginCompressionScreen(traineeName: 'Alexandra'),
  ),
  _Case('Live', () => const LivePracticeScreen(traineeName: 'Alexandra')),
  _Case(
    'SummarySaved',
    () => const SessionCompleteScreen(
      traineeName: 'Alexandra',
      saved: true,
      summary: _summary,
      durationSeconds: 83,
    ),
  ),
  _Case(
    'SummaryInterrupted',
    () => const SessionCompleteScreen(
      traineeName: 'Alexandra',
      saved: false,
      summary: null,
      durationSeconds: 4125,
    ),
  ),
];

void main() {
  setUpAll(() async {
    final FontLoader loader = FontLoader('Montserrat');
    for (final String file in <String>[
      'Montserrat-Light.ttf',
      'Montserrat-Regular.ttf',
      'Montserrat-Medium.ttf',
      'Montserrat-SemiBold.ttf',
      'Montserrat-Bold.ttf',
      'Montserrat-ExtraBold.ttf',
      'Montserrat-Black.ttf',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  });

  for (final Size size in _sizes) {
    for (final double scale in _scales) {
      testWidgets('no screen overflows at ${_label(size)} x$scale', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(
          size.width * _pixelRatio,
          size.height * _pixelRatio,
        );
        tester.view.devicePixelRatio = _pixelRatio;
        tester.view.padding = FakeViewPadding(
          top: _topInset * _pixelRatio,
          bottom: _bottomInset * _pixelRatio,
        );
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        for (final _Case testCase in _cases) {
          final BleController controller = BleController();
          final SessionRepository repository = SessionRepository(
            factory: const _FailingDatabaseFactory(),
            databasePath: 'layout-test.db',
          );

          await tester.pumpWidget(
            _harness(testCase.build(), controller, repository),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            tester.takeException(),
            isNull,
            reason:
                '${testCase.name} overflowed at ${_label(size)} '
                'with text scale $scale',
          );

          // Unmount so the screen's timers and listeners are released.
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      });
    }
  }
}

/// Wraps a screen in the app's theming, scope and text-scale clamp.
Widget _harness(
  Widget screen,
  BleController controller,
  SessionRepository repository,
) {
  return AppScope(
    controller: controller,
    repository: repository,
    child: MaterialApp(
      theme: appThemeData().theme,
      debugShowCheckedModeBanner: false,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: AppLayout.maxTextScale,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: screen,
    ),
  );
}

String _label(Size size) => '${size.width.toInt()}x${size.height.toInt()}';
