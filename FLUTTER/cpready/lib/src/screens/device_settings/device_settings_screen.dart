/// Device Settings: profile, depth K, read-back and factory reset.
///
/// It shows the last values saved on the phone, tries GET_CONFIG on open and
/// after every change, and clearly marks the device as unsupported when no
/// Type 6 report arrives (firmware older than F-01).
///
/// Profile changes are confirmed because each profile has its own calibrated
/// K, so depth readings change with the mode. SET_K and RESET_CONFIG are only
/// sent after explicit user action; nothing is synced silently.

import '../help/help_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/ble/device_config.dart';
import '../../core/ble/kinematic_profile.dart';
import '../../core/history/session_repository.dart';
import '../../core/settings/device_settings.dart';
import '../../widgets/widgets.dart';

/// Full-screen firmware configuration editor.
class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  final TextEditingController _kController = TextEditingController();

  late BleController _controller;
  late SessionRepository _repository;

  DeviceSettings? _settings;
  bool _hasStoredSettings = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _profileSaving = false;
  bool _kSaving = false;
  bool _resetting = false;

  /// True only after a Type 6 report populated the current values.
  bool _readBackSupported = false;

  String? _status;
  bool _statusIsError = false;
  String? _kError;

  /// Reminder shown after a successful profile switch (K was reset).
  bool _profileResetNotice = false;

  bool _initialized = false;
  bool _wasConnected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _controller = AppScope.of(context);
    _repository = AppScope.history(context);
    _wasConnected = _controller.isConnected;
    _controller.addListener(_onConnectionChanged);
    unawaited(_loadAndRefresh());
  }

  @override
  void dispose() {
    _controller.removeListener(_onConnectionChanged);
    _kController.dispose();
    super.dispose();
  }

  /// Restores locally saved values first, then asks the device for Type 6.
  Future<void> _loadAndRefresh() async {
    DeviceSettings? stored;
    try {
      stored = await _repository.loadDeviceSettings();
    } catch (error) {
      debugPrint('Device settings load failed: $error');
    }

    if (!mounted) return;

    final DeviceSettings settings = stored ?? DeviceSettings.defaults();
    setState(() {
      _settings = settings;
      _hasStoredSettings = stored != null;
      _loading = false;
      _kController.text = _formatK(settings.depthK);
    });

    await _refresh();
  }

  /// Reacts to a link drop/reconnect while the screen is open. The screen keeps
  /// local values visible; commands are disabled until the link is back.
  void _onConnectionChanged() {
    if (!mounted) return;

    final bool connected = _controller.isConnected;
    if (connected == _wasConnected) return;
    _wasConnected = connected;

    if (!connected) {
      setState(() {
        _status = AppStrings.deviceSettingsOffline;
        _statusIsError = false;
      });
      return;
    }

    if (!_loading) {
      unawaited(_refresh());
    }
  }

  /// Sends GET_CONFIG and waits for Type 6, then persists the read-back.
  Future<void> _refresh() async {
    if (!mounted ||
        _refreshing ||
        _loading ||
        _profileSaving ||
        _kSaving ||
        _resetting) {
      return;
    }

    if (!_controller.isConnected) {
      setState(() {
        _refreshing = false;
        _status = AppStrings.deviceSettingsOffline;
        _statusIsError = false;
      });
      return;
    }

    setState(() {
      _refreshing = true;
      _status = AppStrings.deviceSettingsRefreshing;
      _statusIsError = false;
    });

    DeviceConfig? config;
    try {
      config = await _controller.requestConfig(
        timeout: AppDurations.configReportTimeout,
      );
    } catch (error) {
      debugPrint('GET_CONFIG failed: $error');
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _status = AppStrings.deviceSettingsReadFailed;
        _statusIsError = true;
      });
      return;
    }

    if (!mounted) return;

    if (config == null) {
      setState(() {
        _refreshing = false;
        _readBackSupported = false;
        _status = AppStrings.deviceSettingsUnsupported;
        _statusIsError = false;
      });
      return;
    }

    final DeviceSettings readBack = DeviceSettings(
      profile: config.profile,
      depthK: config.depthK,
      practiceDurationSec: config.practiceDurationSeconds,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _refreshing = false;
      _readBackSupported = true;
      _settings = readBack;
      _hasStoredSettings = true;
      _kController.text = _formatK(readBack.depthK);
      _kError = null;
      _profileResetNotice = false;
      _status = AppStrings.deviceSettingsReadBack;
      _statusIsError = false;
    });

    final bool saved = await _saveLocally(readBack);
    if (!saved && mounted) {
      setState(() {
        _status = AppStrings.deviceSettingsLocalSaveFailed;
        _statusIsError = true;
      });
    }
  }

  /// Sends SET_K after validating the same 1.00–30.00 range as the firmware.
  Future<void> _setK() async {
    if (_kSaving || _refreshing || !_controller.isConnected) return;

    final String raw = _kController.text.trim().replaceAll(',', '.');
    final double? value = double.tryParse(raw);
    if (value == null ||
        value < AppBleConfig.depthKMin ||
        value > AppBleConfig.depthKMax) {
      setState(() => _kError = AppStrings.deviceSettingsKInvalid);
      return;
    }

    setState(() {
      _kSaving = true;
      _kError = null;
      _status = null;
      _statusIsError = false;
    });

    try {
      await _controller.sendCommand(AppBleConfig.commandSetK(value));
    } catch (error) {
      debugPrint('SET_K failed: $error');
      if (!mounted) return;
      setState(() {
        _kSaving = false;
        _status = AppStrings.deviceSettingsKFailed;
        _statusIsError = true;
      });
      return;
    }

    final DeviceSettings current = _settings ?? DeviceSettings.defaults();
    final DeviceSettings updated = DeviceSettings(
      profile: current.profile,
      depthK: value,
      practiceDurationSec: current.practiceDurationSec,
      updatedAt: DateTime.now(),
    );

    final bool saved = await _saveLocally(updated);
    if (!mounted) return;

    setState(() {
      _kSaving = false;
      _readBackSupported = false;
      _settings = updated;
      _hasStoredSettings = true;
      _kController.text = _formatK(value);
      _status = saved
          ? AppStrings.deviceSettingsKSent
          : AppStrings.deviceSettingsLocalSaveFailed;
      _statusIsError = !saved;
    });
  }

  /// Sends SET_PROFILE only after confirmation, then reads the device back so
  /// the K shown is the new profile's own K.
  Future<void> _selectProfile(KinematicProfile profile) async {
    if (_profileSaving || _refreshing || !_controller.isConnected) return;
    if (profile == _settings?.profile) return;

    final bool confirmed = await confirmProfileChange(context);
    if (!confirmed || !mounted) return;

    setState(() {
      _profileSaving = true;
      _profileResetNotice = false;
      _status = null;
      _statusIsError = false;
    });

    try {
      await _controller.sendCommand(profile.command);
    } catch (error) {
      debugPrint('SET_PROFILE failed: $error');
      if (!mounted) return;
      setState(() {
        _profileSaving = false;
        _status = AppStrings.deviceSettingsProfileFailed;
        _statusIsError = true;
      });
      return;
    }

    final DeviceSettings current = _settings ?? DeviceSettings.defaults();
    final DeviceSettings updated = DeviceSettings(
      profile: profile,
      depthK: null,
      practiceDurationSec: current.practiceDurationSec,
      updatedAt: DateTime.now(),
    );

    final bool saved = await _saveLocally(updated);
    if (!mounted) return;

    setState(() {
      _profileSaving = false;
      _readBackSupported = false;
      _settings = updated;
      _hasStoredSettings = true;
      _kController.clear();
      _kError = null;
      _profileResetNotice = true;
      _status = saved ? null : AppStrings.deviceSettingsLocalSaveFailed;
      _statusIsError = !saved;
    });

    if (saved) await _refresh();
  }

  /// RESET_CONFIG is destructive, so the button is press-and-hold only.
  Future<void> _resetConfig() async {
    if (_resetting || _refreshing || !_controller.isConnected) return;

    setState(() {
      _resetting = true;
      _profileResetNotice = false;
      _status = null;
      _statusIsError = false;
    });

    try {
      await _controller.sendCommand(AppBleConfig.commandResetConfig);
    } catch (error) {
      debugPrint('RESET_CONFIG failed: $error');
      if (!mounted) return;
      setState(() {
        _resetting = false;
        _status = AppStrings.deviceSettingsResetFailed;
        _statusIsError = true;
      });
      return;
    }

    final DeviceSettings reset = DeviceSettings.defaults();
    final bool saved = await _saveLocally(reset);
    if (!mounted) return;

    setState(() {
      _resetting = false;
      _readBackSupported = false;
      _settings = reset;
      _hasStoredSettings = true;
      _kController.clear();
      _kError = null;
      _status = saved
          ? AppStrings.deviceSettingsResetDone
          : AppStrings.deviceSettingsLocalSaveFailed;
      _statusIsError = !saved;
    });
  }

  /// Returns false when the local fallback could not be written; the device
  /// command itself is still reported by the caller.
  Future<bool> _saveLocally(DeviceSettings settings) async {
    try {
      await _repository.saveDeviceSettings(settings);
      return true;
    } catch (error) {
      debugPrint('Device settings save failed: $error');
      return false;
    }
  }

  String _formatK(double? value) =>
      value == null ? '' : value.toStringAsFixed(2);

  String _profileLabel(KinematicProfile profile) => switch (profile) {
    KinematicProfile.manikin => AppStrings.setupProfileManikin,
    KinematicProfile.bench => AppStrings.setupProfileBench,
  };

  String _sourceLabel() {
    if (_readBackSupported) return AppStrings.deviceSettingsSourceDevice;
    if (_hasStoredSettings) return AppStrings.deviceSettingsSourceLocal;
    return AppStrings.deviceSettingsSourceDefault;
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

  TextStyle _sectionStyle() => AppTypography.style(
    size: AppTypography.setupProfileLabelSize,
    weight: FontWeight.bold,
    color: AppColors.flowHeadingText,
  );

  TextStyle _bodyStyle() => AppTypography.style(
    size: AppTypography.flowHelperSize,
    weight: FontWeight.normal,
    color: AppColors.flowHelperText,
  );

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final bool connected = _controller.isConnected;
        final DeviceSettings? settings = _settings;
        final String? status = !connected && !_loading
            ? AppStrings.deviceSettingsOffline
            : _status;
        final bool statusIsError = !connected && !_loading
            ? false
            : _statusIsError;

        return AdaptiveScreen(
          padding: EdgeInsets.only(
            top: AppSpacing.flowTopPadding,
            bottom: AppSpacing.flowActionBottomPadding,
            left: page,
            right: page,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const FlowBackButton(),
                  SizedBox(width: AppSpacing.flowBackTitleGap),
              Expanded(
                child: Text(
                  AppStrings.deviceSettingsTitle,
                  style: AppTypography.style(
                    size: AppTypography.flowTitleSize,
                    weight: AppTypography.headingWeight,
                    color: AppColors.flowHeadingText,
                  ),
                ),
              ),
              
               IconButton(
                tooltip: 'Help & Information',
                icon: const Icon(Icons.help_outline_rounded),
                color: AppColors.flowHeadingText,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const HelpScreen(),
                    ),
                  );
                },
              ),

                ],
              ),
              SizedBox(height: AppSpacing.flowTitleGap),
              Text(AppStrings.deviceSettingsSubtitle, style: _bodyStyle()),
              SizedBox(height: AppSpacing.section),
              if (_loading)
                Text(AppStrings.deviceSettingsLoading, style: _bodyStyle())
              else if (settings != null) ...<Widget>[
                if (status != null) ...<Widget>[
                  _StatusBanner(message: status, isError: statusIsError),
                  SizedBox(height: AppSpacing.item),
                ],
                _CurrentConfigPanel(
                  settings: settings,
                  profileLabel: _profileLabel(settings.profile),
                  sourceLabel: _sourceLabel(),
                ),
                SizedBox(height: AppSpacing.section),
                _ProfilePanel(
                  profile: settings.profile,
                  saving: _profileSaving,
                  enabled:
                      connected &&
                      !_refreshing &&
                      !_profileSaving &&
                      !_resetting,
                  resetNotice: _profileResetNotice,
                  sectionStyle: _sectionStyle(),
                  bodyStyle: _bodyStyle(),
                  onChanged: _selectProfile,
                ),
                SizedBox(height: AppSpacing.section),
                _KPanel(
                  controller: _kController,
                  saving: _kSaving,
                  enabled: connected && !_refreshing && !_kSaving,
                  error: _kError,
                  sectionStyle: _sectionStyle(),
                  bodyStyle: _bodyStyle(),
                  fieldBorder: _fieldBorder(),
                  onChanged: () {
                    if (_kError != null) setState(() => _kError = null);
                  },
                  onSetK: _setK,
                ),
                SizedBox(height: AppSpacing.section),
                _ResetPanel(
                  resetting: _resetting,
                  enabled: connected && !_refreshing && !_resetting,
                  sectionStyle: _sectionStyle(),
                  bodyStyle: _bodyStyle(),
                  onComplete: _resetConfig,
                ),
                SizedBox(height: AppSpacing.section),
                FlatActionButton(
                  label: _refreshing
                      ? AppStrings.deviceSettingsRefreshing
                      : AppStrings.deviceSettingsRefresh,
                  onPressed:
                      connected &&
                          !_refreshing &&
                          !_profileSaving &&
                          !_kSaving &&
                          !_resetting
                      ? _refresh
                      : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Current values, with their source so local fallback is never mistaken for
/// an authoritative device read.
class _CurrentConfigPanel extends StatelessWidget {
  const _CurrentConfigPanel({
    required this.settings,
    required this.profileLabel,
    required this.sourceLabel,
  });

  final DeviceSettings settings;
  final String profileLabel;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = AppTypography.style(
      size: AppTypography.setupProfileLabelSize,
      weight: FontWeight.bold,
      color: AppColors.flowHeadingText,
    );
    final TextStyle bodyStyle = AppTypography.style(
      size: AppTypography.flowHelperSize,
      weight: FontWeight.normal,
      color: AppColors.flowHelperText,
    );

    return FlowPanel(
      padding: EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(AppStrings.deviceSettingsCurrent, style: labelStyle),
          SizedBox(height: AppSpacing.item),
          _SettingRow(
            label: AppStrings.deviceSettingsProfile,
            value: profileLabel,
            bodyStyle: bodyStyle,
          ),
          SizedBox(height: AppSpacing.small),
          _SettingRow(
            label: AppStrings.deviceSettingsDepthK,
            value: settings.depthK == null
                ? AppStrings.deviceSettingsUnknown
                : settings.depthK!.toStringAsFixed(2),
            bodyStyle: bodyStyle,
          ),
          SizedBox(height: AppSpacing.small),
          _SettingRow(
            label: AppStrings.deviceSettingsDuration,
            value: AppStrings.deviceSettingsSeconds(
              settings.practiceDurationSec,
            ),
            bodyStyle: bodyStyle,
          ),
          SizedBox(height: AppSpacing.small),
          _SettingRow(
            label: AppStrings.deviceSettingsSource,
            value: sourceLabel,
            bodyStyle: bodyStyle,
          ),
        ],
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({
    required this.profile,
    required this.saving,
    required this.enabled,
    required this.resetNotice,
    required this.sectionStyle,
    required this.bodyStyle,
    required this.onChanged,
  });

  final KinematicProfile profile;
  final bool saving;
  final bool enabled;
  final bool resetNotice;
  final TextStyle sectionStyle;
  final TextStyle bodyStyle;
  final ValueChanged<KinematicProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    return FlowPanel(
      padding: EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(AppStrings.deviceSettingsProfileSection, style: sectionStyle),
          SizedBox(height: AppSpacing.small),
          Text(
            AppStrings.deviceSettingsProfileHelper,
            style: bodyStyle.copyWith(color: AppColors.summaryFailedText),
          ),
          SizedBox(height: AppSpacing.item),
          IgnorePointer(
            ignoring: !enabled || saving,
            child: ProfileSelector(profile: profile, onChanged: onChanged),
          ),
          if (resetNotice) ...<Widget>[
            SizedBox(height: AppSpacing.small),
            Text(
              AppStrings.profileSwitchResetNotice,
              style: bodyStyle.copyWith(color: AppColors.connected),
            ),
          ],
        ],
      ),
    );
  }
}

class _KPanel extends StatelessWidget {
  const _KPanel({
    required this.controller,
    required this.saving,
    required this.enabled,
    required this.error,
    required this.sectionStyle,
    required this.bodyStyle,
    required this.fieldBorder,
    required this.onChanged,
    required this.onSetK,
  });

  final TextEditingController controller;
  final bool saving;
  final bool enabled;
  final String? error;
  final TextStyle sectionStyle;
  final TextStyle bodyStyle;
  final OutlineInputBorder fieldBorder;
  final VoidCallback onChanged;
  final Future<void> Function() onSetK;

  @override
  Widget build(BuildContext context) {
    return FlowPanel(
      padding: EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(AppStrings.deviceSettingsKSection, style: sectionStyle),
          SizedBox(height: AppSpacing.small),
          Text(AppStrings.deviceSettingsKHelper, style: bodyStyle),
          SizedBox(height: AppSpacing.item),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppSizes.flowFieldHeight),
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              style: AppTypography.style(
                size: AppTypography.flowFieldTextSize,
                weight: FontWeight.normal,
                color: AppColors.flowFieldText,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.flowPanelBackground,
                hintText: AppStrings.deviceSettingsKHint,
                hintStyle: AppTypography.style(
                  size: AppTypography.flowFieldTextSize,
                  weight: FontWeight.normal,
                  color: AppColors.flowFieldHint,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.flowFieldPaddingH,
                ),
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder,
                disabledBorder: fieldBorder,
              ),
            ),
          ),
          if (error != null) ...<Widget>[
            SizedBox(height: AppSpacing.small),
            Text(
              error!,
              style: bodyStyle.copyWith(color: AppColors.statusError),
            ),
          ],
          SizedBox(height: AppSpacing.item),
          FlatActionButton(
            label: saving
                ? AppStrings.deviceSettingsKSending
                : AppStrings.deviceSettingsKSet,
            onPressed: enabled ? () => unawaited(onSetK()) : null,
          ),
        ],
      ),
    );
  }
}

class _ResetPanel extends StatelessWidget {
  const _ResetPanel({
    required this.resetting,
    required this.enabled,
    required this.sectionStyle,
    required this.bodyStyle,
    required this.onComplete,
  });

  final bool resetting;
  final bool enabled;
  final TextStyle sectionStyle;
  final TextStyle bodyStyle;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context) {
    return FlowPanel(
      padding: EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(AppStrings.deviceSettingsResetSection, style: sectionStyle),
          SizedBox(height: AppSpacing.small),
          Text(
            AppStrings.deviceSettingsResetWarning,
            style: bodyStyle.copyWith(color: AppColors.summaryFailedText),
          ),
          SizedBox(height: AppSpacing.item),
          HoldFillButton(
            label: AppStrings.deviceSettingsResetHold,
            duration: AppDurations.resetConfigHold,
            enabled: enabled && !resetting,
            onComplete: onComplete,
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.item),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.summaryFailedBackground
            : AppColors.flowPanelBackground,
        borderRadius: BorderRadius.circular(AppSizes.flowFieldRadius),
        border: Border.all(
          color: isError ? AppColors.statusError : AppColors.flowPanelBorder,
          width: AppSizes.flowPanelBorderWidth,
        ),
      ),
      child: Text(
        message,
        style: AppTypography.style(
          size: AppTypography.flowHelperSize,
          weight: FontWeight.normal,
          color: isError
              ? AppColors.summaryFailedText
              : AppColors.flowHelperText,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.bodyStyle,
  });

  final String label;
  final String value;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label, style: bodyStyle)),
        SizedBox(width: AppSpacing.item),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: bodyStyle.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.flowFieldText,
            ),
          ),
        ),
      ],
    );
  }
}
