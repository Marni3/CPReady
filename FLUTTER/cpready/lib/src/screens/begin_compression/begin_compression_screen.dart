/// Countdown screen shown after Calibration: a 3 → 2 → 1 count, then the live
/// session starts on its own.
///
/// Full-screen and all white, with no back button: the flow only moves forward
/// from here. When the count reaches zero the app restores the normal session
/// duration, sends START (the firmware expects it once the baseline is ready)
/// and replaces this screen with the live session, so the app timer and the
/// firmware session clock start together.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../widgets/widgets.dart';

/// Countdown between calibration and the live session.
class BeginCompressionScreen extends StatefulWidget {
  /// Trainee name captured on the setup screen; carried through the flow.
  final String traineeName;

  const BeginCompressionScreen({super.key, required this.traineeName});

  @override
  State<BeginCompressionScreen> createState() => _BeginCompressionScreenState();
}

class _BeginCompressionScreenState extends State<BeginCompressionScreen> {
  Timer? _timer;
  bool _started = false;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = AppDurations.countdownMs ~/ AppDurations.countdownTickMs;
    _timer = Timer.periodic(AppDurations.countdownTick, (_) => _tick());
  }

  void _tick() {
    if (!mounted || _started) return;
    if (_remaining <= 1) {
      unawaited(_startSession());
    } else {
      setState(() => _remaining -= 1);
    }
  }

  Future<void> _startSession() async {
    if (_started || !mounted) return;
    _started = true;
    _timer?.cancel();

    final controller = AppScope.of(context);

    // The manikin trial shortens the firmware's auto-stop to 15 seconds, and
    // that duration survives a killed app. Setting it here makes every
    // practice session use the normal length regardless of what ran before.
    try {
      await controller.sendCommand(
        AppBleConfig.commandSetTime(AppDurations.practiceSessionSeconds),
      );
    } catch (error) {
      // The live screen surfaces a dropped link; keep the flow moving.
      debugPrint('Practice duration set failed: $error');
    }

    try {
      await controller.sendCommand(AppBleConfig.commandStart);
    } catch (error) {
      // The live screen surfaces a dropped link; keep the flow moving.
      debugPrint('Session start failed: $error');
    }

    if (!mounted) return;
    context.pushReplacementNamed(
      AppRoutes.livePractice,
      extra: widget.traineeName,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return PopScope(
      canPop: false,
      child: AdaptiveScreen(
        padding: EdgeInsets.symmetric(horizontal: page),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$_remaining',
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.countdownNumberSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.countdownNumberGap),
              Image.asset(
                AppAssets.beginSession,
                width: AppSizes.countdownImageSize,
                height: AppSizes.countdownImageSize,
                fit: BoxFit.contain,
              ),
              SizedBox(height: AppSpacing.countdownImageGap),
              Text(
                AppStrings.beginCompressionTitle,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.countdownTitleSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.countdownHelperGap),
              Text(
                AppStrings.beginCompressionBody,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.countdownHelperSize,
                  weight: FontWeight.normal,
                  color: AppColors.flowHelperText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
