/// Practice setup: capture the trainee name that the session is filed under
/// and pick the device's kinematic profile and session duration.
///
/// Full-screen (no top header, no bottom nav), like the Step-by-step Guide:
/// a small back arrow beside the title, the big heading, the name field with
/// its helper line, the training-mode options, the session duration picker,
/// and the Continue button near the bottom.
///
/// The name and duration are carried forward. The selected profile is the last
/// value known to the app: it is loaded from the local settings row and sent to
/// the device only when the user confirms a change. The flow is:
/// Setup → Hand Placement → Calibration → Live Practice (starts on first compression).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/kinematic_profile.dart';
import '../../core/history/session_repository.dart';
import '../../core/practice_session_args.dart';
import '../../core/settings/device_settings.dart';
import '../../widgets/widgets.dart';

/// Session lengths offered on the setup screen. 0 = unlimited (manual stop).
const List<int> _durationOptions = <int>[30, 60, 120, 0];

/// Practice setup screen.
class PracticeSetupScreen extends StatefulWidget {
  const PracticeSetupScreen({super.key});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _participantCode =
      TextEditingController(text: 'P001');
  final TextEditingController _experiment =
      TextEditingController(text: 'practice');
  final TextEditingController _notes = TextEditingController();

  bool _telemetryEnabled = false;

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
    _participantCode.dispose();
    _experiment.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      (!_telemetryEnabled || _participantCode.text.trim().isNotEmpty);

  void _setTelemetryEnabled(bool value) {
    setState(() => _telemetryEnabled = value);
  }

  /// Restores the last known mode so the selector does not claim MANIKIN when
  /// the device was last switched to BENCH.
  Future<void> _loadSettings() async {
    try {
      final DeviceSettings? settings = await _repository?.loadDeviceSettings();
      if (!mounted || settings == null) return;
      setState(() {
        _profile = settings.profile;
        // Only show a value the picker can represent; firmware-only trial
        // lengths (for example the 15 s manikin window) fall back to default.
        _practiceDurationSec = _durationOptions.contains(
          settings.practiceDurationSec,
        )
            ? settings.practiceDurationSec
            : AppDeviceSettings.defaultPracticeDurationSec;
      });
    } catch (error) {
      debugPrint('Device settings load failed: $error');
    }
  }

  void _continue() {
    if (!_valid) return;
    final controller = AppScope.of(context);
    controller.telemetryEnabled = _telemetryEnabled;
    controller.telemetryParticipantCode = _participantCode.text.trim();
    controller.telemetryExperiment = _experiment.text.trim();
    controller.telemetryNotes = _notes.text.trim();
    context.pushNamed(
      AppRoutes.handPlacement,
      extra: PracticeSessionArgs(
        traineeName: _name.text.trim(),
        practiceDurationSec: _practiceDurationSec,
      ),
    );
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

  Widget _telemetryField({
    required TextEditingController controller,
    required String label,
    required String hint,
    ValueChanged<String>? onChanged,
    TextCapitalization capitalization = TextCapitalization.sentences,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textCapitalization: capitalization,
      autocorrect: capitalization != TextCapitalization.characters,
      style: AppTypography.style(
        size: AppTypography.flowFieldTextSize,
        weight: FontWeight.normal,
        color: AppColors.flowFieldText,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.flowPanelBackground,
        labelText: label,
        labelStyle: AppTypography.style(
          size: AppTypography.flowHelperSize,
          weight: FontWeight.normal,
          color: AppColors.flowFieldHint,
        ),
        hintText: hint,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );
    final bool telemetrySupported = AppScope.of(context).supportsRawTelemetry;

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
                AppStrings.setupDurationTitle,
                style: AppTypography.style(
                  size: AppTypography.setupProfileLabelSize,
                  weight: FontWeight.bold,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.flowHelperGap),
              Text(
                AppStrings.setupDurationHelper,
                style: AppTypography.style(
                  size: AppTypography.flowHelperSize,
                  weight: FontWeight.normal,
                  color: AppColors.flowHelperText,
                ),
              ),
              SizedBox(height: AppSpacing.flowHelperGap),
              _DurationPicker(
                value: _practiceDurationSec,
                onChanged: (value) {
                  setState(() {
                    _practiceDurationSec = value;
                  });
                },
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
              SizedBox(height: AppSpacing.setupProfileTopGap),
              Text(
                AppStrings.setupTelemetryTitle,
                style: AppTypography.style(
                  size: AppTypography.setupProfileLabelSize,
                  weight: FontWeight.bold,
                  color: AppColors.flowHeadingText,
                ),
              ),
              SizedBox(height: AppSpacing.flowHelperGap),
              Text(
                AppStrings.setupTelemetryBody,
                style: AppTypography.style(
                  size: AppTypography.flowHelperSize,
                  weight: FontWeight.normal,
                  color: AppColors.flowHelperText,
                ),
              ),
              SizedBox(height: AppSpacing.flowHelperGap),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      AppStrings.setupTelemetryToggle,
                      style: AppTypography.style(
                        size: AppTypography.flowFieldTextSize,
                        weight: FontWeight.w600,
                        color: AppColors.flowHeadingText,
                      ),
                    ),
                  ),
                  Switch(
                    value: _telemetryEnabled && telemetrySupported,
                    onChanged: telemetrySupported ? _setTelemetryEnabled : null,
                  ),
                ],
              ),
              if (!telemetrySupported) ...<Widget>[
                Text(
                  AppStrings.setupTelemetryUnsupported,
                  style: AppTypography.style(
                    size: AppTypography.flowHelperSize,
                    weight: FontWeight.normal,
                    color: AppColors.flowHelperText,
                  ),
                ),
              ],
              if (_telemetryEnabled && telemetrySupported) ...<Widget>[
                SizedBox(height: AppSpacing.flowHelperGap),
                _telemetryField(
                  controller: _participantCode,
                  label: AppStrings.setupParticipantCodeLabel,
                  hint: AppStrings.setupParticipantCodeHint,
                  onChanged: (_) => setState(() {}),
                  capitalization: TextCapitalization.characters,
                ),
                SizedBox(height: AppSpacing.flowHelperGap),
                _telemetryField(
                  controller: _experiment,
                  label: AppStrings.setupExperimentLabel,
                  hint: AppStrings.setupExperimentHint,
                ),
                SizedBox(height: AppSpacing.flowHelperGap),
                _telemetryField(
                  controller: _notes,
                  label: AppStrings.setupNotesLabel,
                  hint: AppStrings.setupNotesHint,
                ),
                SizedBox(height: AppSpacing.flowHelperGap),
                Text(
                  AppStrings.setupTelemetryCodeHelper,
                  style: AppTypography.style(
                    size: AppTypography.flowHelperSize,
                    weight: FontWeight.normal,
                    color: AppColors.flowHelperText,
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
// ============================================================
// DURATION PICKER
// ============================================================

/// Session-length choice: tappable rows that match the training-mode selector.
class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  static String _label(int seconds) {
    switch (seconds) {
      case 30:
        return AppStrings.setupDuration30s;
      case 60:
        return AppStrings.setupDuration60s;
      case 120:
        return AppStrings.setupDuration120s;
      case 0:
        return AppStrings.setupDurationUnlimited;
      default:
        return '${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < _durationOptions.length; i++) ...<Widget>[
          _DurationOption(
            label: _label(_durationOptions[i]),
            selected: value == _durationOptions[i],
            onTap: () => onChanged(_durationOptions[i]),
          ),
          if (i != _durationOptions.length - 1)
            SizedBox(height: AppSpacing.setupProfileOptionGap),
        ],
      ],
    );
  }
}

/// One row of [DurationPicker].
class _DurationOption extends StatelessWidget {
  const _DurationOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = selected
        ? AppColors.profileOptionSelectedBorder
        : AppColors.profileOptionBorder;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: AppSizes.profileOptionMinHeight,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.profileOptionPaddingH,
            vertical: AppSpacing.profileOptionPaddingV,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.profileOptionSelectedBackground
                : AppColors.profileOptionBackground,
            borderRadius: BorderRadius.circular(AppSizes.profileOptionRadius),
            border: Border.all(
              color: border,
              width: AppSizes.profileOptionBorderWidth,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AppSizes.profileOptionIndicatorSize,
                height: AppSizes.profileOptionIndicatorSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.profileOptionIndicator
                        : AppColors.profileOptionBorder,
                    width: AppSizes.profileOptionIndicatorBorderWidth,
                  ),
                ),
                child: selected
                    ? Container(
                        width: AppSizes.profileOptionIndicatorDotSize,
                        height: AppSizes.profileOptionIndicatorDotSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.profileOptionIndicator,
                        ),
                      )
                    : null,
              ),
              SizedBox(width: AppSpacing.profileOptionIndicatorGap),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.style(
                    size: AppTypography.profileOptionTitleSize,
                    weight: FontWeight.bold,
                    color: AppColors.profileOptionText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
