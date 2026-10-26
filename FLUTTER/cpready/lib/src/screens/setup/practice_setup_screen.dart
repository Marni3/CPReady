/// Practice setup: capture the trainee name that the session is filed under
/// and pick the device's kinematic profile.
///
/// Full-screen (no top header, no bottom nav), like the Step-by-step Guide:
/// a small back arrow beside the title, the big heading, the name field with
/// its helper line, the training-mode options, and the Continue button near
/// the bottom.
///
/// The name is the only value carried forward. The selected profile is the last
/// value known to the app: it is loaded from the local settings row and sent to
/// the device only when the user confirms a change. The flow is:
/// Setup → Hand Placement → Calibration → countdown → Live Practice.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/kinematic_profile.dart';
import '../../core/history/session_repository.dart';
import '../../core/settings/device_settings.dart';
import '../../widgets/widgets.dart';

/// Practice setup screen.
class PracticeSetupScreen extends StatefulWidget {
  const PracticeSetupScreen({super.key});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  final TextEditingController _name = TextEditingController();

  KinematicProfile _profile = KinematicProfile.manikin;
  int _practiceDurationSec = AppDeviceSettings.defaultPracticeDurationSec;
  bool _profileFailed = false;
  bool _profileResetNotice = false;
  bool _profileSaving = false;
  bool _settingsLoaded = false;
  SessionRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    _repository = AppScope.history(context);
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  /// Restores the last known mode so the selector does not claim MANIKIN when
  /// the device was last switched to BENCH.
  Future<void> _loadSettings() async {
    try {
      final DeviceSettings? settings = await _repository?.loadDeviceSettings();
      if (!mounted || settings == null) return;
      setState(() {
        _profile = settings.profile;
        _practiceDurationSec = settings.practiceDurationSec;
      });
    } catch (error) {
      debugPrint('Device settings load failed: $error');
    }
  }

  void _continue() {
    if (!_valid) return;
    context.pushNamed(AppRoutes.handPlacement, extra: _name.text.trim());
  }

  /// Sends the profile only after the user confirms the K-reset warning.
  ///
  /// A failed write restores the previous option, because the device kept its
  /// old profile; the error line then says the change did not go through.
  Future<void> _selectProfile(KinematicProfile profile) async {
    if (profile == _profile || _profileSaving) return;

    final bool confirmed = await confirmProfileChange(context);
    if (!confirmed || !mounted) return;

    final KinematicProfile previous = _profile;
    final SessionRepository? repository = _repository;
    setState(() {
      _profile = profile;
      _profileFailed = false;
      _profileResetNotice = false;
      _profileSaving = true;
    });

    try {
      await AppScope.of(context).sendCommand(profile.command);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = previous;
        _profileFailed = true;
        _profileSaving = false;
      });
      return;
    }

    final DeviceSettings updated = DeviceSettings(
      profile: profile,
      depthK: null,
      practiceDurationSec: _practiceDurationSec,
      updatedAt: DateTime.now(),
    );

    try {
      await repository?.saveDeviceSettings(updated);
    } catch (error) {
      debugPrint('Device settings save failed: $error');
    }

    if (!mounted) return;
    setState(() {
      _profileSaving = false;
      _profileResetNotice = true;
    });
  }

  OutlineInputBorder _fieldBorder() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.flowFieldRadius),
      borderSide: BorderSide(
        color: AppColors.flowPanelBorder,
        width: AppSizes.flowPanelBorderWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return AdaptiveScreen(
      padding: EdgeInsets.only(
        top: AppSpacing.flowTopPadding,
        bottom: AppSpacing.flowActionBottomPadding,
        left: page,
        right: page,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const FlowBackButton(),
                  SizedBox(width: AppSpacing.flowBackTitleGap),
                  Expanded(
                    child: Text(
                      AppStrings.setupTitle,
                      style: AppTypography.style(
                        size: AppTypography.flowTitleSize,
                        weight: AppTypography.headingWeight,
                        color: AppColors.flowHeadingText,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.flowTitleGap),
              Text(
                AppStrings.setupHeading,
                style: AppTypography.style(
                  size: AppTypography.flowHeadingSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.flowHeadingGap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppSizes.flowFieldHeight,
                ),
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  style: AppTypography.style(
                    size: AppTypography.flowFieldTextSize,
                    weight: FontWeight.normal,
                    color: AppColors.flowFieldText,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.flowPanelBackground,
                    hintText: AppStrings.setupNameHint,
                    hintStyle: AppTypography.style(
                      size: AppTypography.flowFieldTextSize,
                      weight: FontWeight.normal,
                      color: AppColors.flowFieldHint,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.flowFieldPaddingH,
                    ),
                    border: _fieldBorder(),
                    enabledBorder: _fieldBorder(),
                    focusedBorder: _fieldBorder(),
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.flowHelperGap),
              Text(
                AppStrings.setupHelper,
                style: AppTypography.style(
                  size: AppTypography.flowHelperSize,
                  weight: FontWeight.normal,
                  color: AppColors.flowHelperText,
                ),
              ),
              SizedBox(height: AppSpacing.setupProfileTopGap),
              Text(
                AppStrings.setupTrainingMode,
                style: AppTypography.style(
                  size: AppTypography.setupProfileLabelSize,
                  weight: FontWeight.bold,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.setupProfileTitleGap),
              IgnorePointer(
                ignoring: _profileSaving,
                child: ProfileSelector(
                  profile: _profile,
                  onChanged: _selectProfile,
                ),
              ),
              if (_profileResetNotice) ...<Widget>[
                SizedBox(height: AppSpacing.flowHelperGap),
                Text(
                  AppStrings.profileSwitchResetNotice,
                  style: AppTypography.style(
                    size: AppTypography.flowHelperSize,
                    weight: FontWeight.normal,
                    color: AppColors.connected,
                  ),
                ),
              ],
              if (_profileFailed) ...<Widget>[
                SizedBox(height: AppSpacing.flowHelperGap),
                Text(
                  AppStrings.setupProfileSendFailed,
                  style: AppTypography.style(
                    size: AppTypography.flowHelperSize,
                    weight: FontWeight.normal,
                    color: AppColors.statusError,
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.section),
            child: FlatActionButton(
              label: AppStrings.setupContinue,
              onPressed: _valid ? _continue : null,
            ),
          ),
        ],
      ),
    );
  }
}
