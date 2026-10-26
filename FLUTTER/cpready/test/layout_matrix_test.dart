/// Layout regression gate: every screen, at every phone size the app supports,
/// under each Android system font setting.
///
/// Size and type follow the app's own bounded scale, not the system font
/// setting, so the four scale cases must render identically; they stay in the
/// matrix to catch any layout that starts depending on the setting again.
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
import 'package:cpready/src/core/audio/voice_coach.dart';
import 'package:cpready/src/core/ble/ble_controller.dart';
import 'package:cpready/src/core/history/session_repository.dart';
import 'package:cpready/src/core/metrics/cpr_metrics.dart';
import 'package:cpready/src/screens/begin_compression/begin_compression_screen.dart';
import 'package:cpready/src/screens/calibration/calibration_screen.dart';
import 'package:cpready/src/screens/device_settings/device_settings_screen.dart';
import 'package:cpready/src/screens/guide/guide_screen.dart';
import 'package:cpready/src/screens/hand_placement/hand_placement_screen.dart';
import 'package:cpready/src/screens/home/home_screen.dart';
import 'package:cpready/src/screens/live_practice/live_practice_screen.dart';
import 'package:cpready/src/screens/manikin_calibration/manikin_calibration_screen.dart';
import 'package:cpready/src/screens/practice/practice_screen.dart';
import 'package:cpready/src/screens/session_complete/session_complete_screen.dart';
import 'package:cpready/src/screens/setup/practice_setup_screen.dart';
import 'package:cpready/src/theme/app_theme.dart';
import 'package:cpready/main.dart';

/// Screen sizes the layout must survive, in logical pixels: the supported
/// floor, a compact phone, a standard phone, a large phone and an extra-large
/// phone.
const List<Size> _sizes = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(393, 852),
  Size(430, 932),
  Size(480, 1040),
];

/// Android font settings to exercise: default, increased, large and the
/// accessibility maximum. The app ignores all four.
const List<double> _scales = <double>[1.0, 1.3, 1.5, 2.0];

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
    () => const HandPlacementScreen(traineeName: 'Alexandra Konstantinopoulos'),
  ),
  _Case(
    'Calibration',
    () => const CalibrationScreen(traineeName: 'Alexandra Konstantinopoulos'),
  ),
  _Case(
    'Countdown',
    () => const BeginCompressionScreen(
      traineeName: 'Alexandra Konstantinopoulos',
    ),
  ),
  _Case(
    'Live',
    () => const LivePracticeScreen(traineeName: 'Alexandra Konstantinopoulos'),
  ),
  _Case('ManikinCalibration', ManikinCalibrationScreen.new),
  _Case('DeviceSettings', DeviceSettingsScreen.new),
  _Case(
    'SummarySaved',
    () => const SessionCompleteScreen(
      traineeName: 'Alexandra Konstantinopoulos',
      reason: SessionEndReason.completed,
      summary: _summary,
      durationSeconds: 83,
    ),
  ),
  _Case(
    'SummaryInterrupted',
    () => const SessionCompleteScreen(
      traineeName: 'Alexandra Konstantinopoulos',
      reason: SessionEndReason.interrupted,
      summary: null,
      durationSeconds: 4125,
    ),
  ),
  _Case(
    'SummaryUnavailable',
    () => const SessionCompleteScreen(
      traineeName: 'Alexandra Konstantinopoulos',
      reason: SessionEndReason.resultsUnavailable,
      summary: null,
      durationSeconds: 12,
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
        _configureView(tester, size, scale: scale);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        for (final _Case testCase in _cases) {
          await _pumpCase(tester, testCase);
          expect(
            tester.takeException(),
            isNull,
            reason:
                '${testCase.name} overflowed at ${_label(size)} '
                'with text scale $scale',
          );
        }
      });
    }
  }

  testWidgets('system font setting does not change typography', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(393, 852), scale: 1.0);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    Future<Size> measureAt(double scale) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(
        _harness(
          Center(
            child: Text(
              'Calibration',
              style: AppTypography.style(
                size: AppTypography.flowTitleSize,
                weight: AppTypography.headingWeight,
              ),
            ),
          ),
          BleController(),
          SessionRepository(
            factory: const _FailingDatabaseFactory(),
            databasePath: 'layout-test.db',
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.text('Calibration'));
    }

    final Size atDefault = await measureAt(1.0);
    final Size atDouble = await measureAt(2.0);
    expect(atDouble, atDefault);
  });

  testWidgets('setup keeps working with the keyboard open', (
    WidgetTester tester,
  ) async {
    // A keyboard covers the bottom third of the screen while the name field
    // has focus; the form must scroll rather than overflow.
    const double keyboard = 300;
    for (final Size size in _sizes) {
      for (final double scale in _scales) {
        _configureView(tester, size, scale: scale);
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboard * _pixelRatio,
        );
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pumpCase(tester, const _Case('Setup', PracticeSetupScreen.new));
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Setup overflowed with the keyboard open at ${_label(size)} '
              'with text scale $scale',
        );
      }
    }
  });
}

/// Applies one phone size, text scale and inset set to the test view.
void _configureView(WidgetTester tester, Size size, {required double scale}) {
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
  AppScale.update(size);
}

/// Pumps one screen and unmounts it again so its timers are released.
Future<void> _pumpCase(WidgetTester tester, _Case testCase) async {
  final BleController controller = BleController();
  final SessionRepository repository = SessionRepository(
    factory: const _FailingDatabaseFactory(),
    databasePath: 'layout-test.db',
  );

  await tester.pumpWidget(_harness(testCase.build(), controller, repository));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

/// Wraps a screen in the app's theming, scope and root media overrides, the
/// same way the running app does: the design factors follow the window and the
/// system font setting is replaced with no scaling.
Widget _harness(
  Widget screen,
  BleController controller,
  SessionRepository repository,
) {
  return AppScope(
    controller: controller,
    repository: repository,
    voiceCoach: const SilentVoiceCoach(),
    child: MaterialApp(
      theme: appThemeData().theme,
      debugShowCheckedModeBanner: false,
      home: screen,
      builder: (BuildContext context, Widget? child) {
        AppScale.update(MediaQuery.sizeOf(context));
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.noScaling),
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
  );
}

String _label(Size size) => '${size.width.toInt()}x${size.height.toInt()}';
