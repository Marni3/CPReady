/// Tab 1 — Home.
///
/// Layout: header, welcome card, and device connection card.
/// Responsive layout for different screen sizes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
import '../../core/ble/kinematic_profile.dart';
import '../../core/settings/device_settings.dart';
import '../../widgets/widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          ScreenHeader(
            pageLabel: AppStrings.homeHeaderPage,
          ),

          Expanded(
            child: ContentBounds(
              child: LayoutBuilder(
                builder: (
                  BuildContext context,
                  BoxConstraints constraints,
                ) {
                  final double availableHeight =
                      constraints.maxHeight;

                  // Responsive spacing.
                  final double topSpacing =
                      (availableHeight * 0.04).clamp(16.0, 32.0);

                  final double bottomSpacing =
                      (availableHeight * 0.04).clamp(16.0, 28.0);

                  final double sectionGap =
                      (availableHeight * 0.035).clamp(16.0, 26.0);

                  // The device card occupies a moderate portion
                  // of the available height without being fixed.
                  final double deviceCardMinHeight =
                      availableHeight * 0.62;

                  return SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: page,
                      right: page,
                      top: topSpacing,
                      bottom: bottomSpacing,
                    ),
                    child: Column(
                      children: <Widget>[
                        const _WelcomeCard(),

                        SizedBox(
                          height: sectionGap,
                        ),

                        _DeviceCard(
                          controller: controller,
                          minHeight: deviceCardMinHeight,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome card
// ---------------------------------------------------------------------------

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = AppTypography.style(
      size: AppTypography.homeWelcomeSize,
      weight: AppTypography.headingWeight,
      color: AppColors.homeWelcomeText,
    );

    final TextStyle subtitleStyle = AppTypography.style(
      size: AppTypography.homeWelcomeSubtitleSize,
      weight: AppTypography.headingWeight,
      color: AppColors.homeWelcomeText,
    );

    final double titleWidth = _measure(
      AppStrings.homeWelcomeTitle,
      titleStyle,
    );

    final double subtitleWidth = _measure(
      AppStrings.homeWelcomeSubtitle,
      subtitleStyle,
    );

    final double subtitleSize =
        AppTypography.homeWelcomeSubtitleSize *
        (titleWidth / subtitleWidth);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: AppSizes.homeWelcomeCardMinHeight,
      ),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(
        left: AppSpacing.homeWelcomeInset,
        right: AppSpacing.homeCardPadding,
        top: AppSpacing.homeCardPadding,
        bottom: AppSpacing.homeCardPadding,
      ),
      decoration: BoxDecoration(
        gradient: AppGradients.brandVertical,
        borderRadius: BorderRadius.circular(
          AppSizes.homeCardRadius,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            AppStrings.homeWelcomeTitle,
            style: titleStyle,
          ),

          SizedBox(
            height: AppSpacing.homeWelcomeGap,
          ),

          Text(
            AppStrings.homeWelcomeSubtitle,
            maxLines: 1,
            softWrap: false,
            style: subtitleStyle.copyWith(
              fontSize: subtitleSize,
            ),
          ),
        ],
      ),
    );
  }

  static double _measure(
    String text,
    TextStyle style,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final double width = painter.width;

    painter.dispose();

    return width;
  }
}

// ---------------------------------------------------------------------------
// Device connection card
// ---------------------------------------------------------------------------

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.controller,
    required this.minHeight,
  });

  final BleController controller;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (
        BuildContext context,
        Widget? _,
      ) {
        final bool connected = controller.isConnected;
        final bool busy = controller.isBusy;

        return Container(
          width: double.infinity,

          constraints: BoxConstraints(
            minHeight: minHeight,
          ),

          alignment: Alignment.center,

          padding: EdgeInsets.all(
            AppSpacing.homeCardPadding,
          ),

          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(
              AppSizes.homeCardRadius,
            ),
            border: Border.all(
              color: AppColors.homeCardBorder,
              width: AppSizes.homeCardBorderWidth,
            ),
          ),

          child: (busy || connected)
              ? _ConnectingContent(
                  connected: connected,
                  onCalibrate: () => unawaited(
                    _openManikinCalibration(context),
                  ),
                  onSettings: () => context.pushNamed(
                    AppRoutes.deviceSettings,
                  ),
                )
              : _NotConnectedContent(
                  controller: controller,
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Not connected
// ---------------------------------------------------------------------------

class _NotConnectedContent extends StatelessWidget {
  const _NotConnectedContent({
    required this.controller,
  });

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(
            AppSpacing.homeBluetoothImagePadding,
          ),
         child: Image(
          image: AssetImage(
            AppAssets.bluetoothUnconnected,
          ),
          width: AppSizes.homeBluetoothImageSize * 1.50,
          height: AppSizes.homeBluetoothImageSize * 1.50,
          fit: BoxFit.contain,
        ),
        ),

        SizedBox(
          height: AppSpacing.item + 24,
        ),

        Text(
          AppStrings.homeDeviceNoneTitle,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeCardTitleSize,
            weight: FontWeight.bold,
            color: AppColors.homeCardText,
          ),
        ),

        SizedBox(
          height: AppSpacing.small,
        ),

        Text(
          AppStrings.homeDeviceNoneSubtitle,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeCardSubtitleSize,
            weight: FontWeight.normal,
            color: AppColors.homeCardText,
          ),
        ),

        SizedBox(
          height: AppSpacing.item,
        ),

        _GradientButton(
          label: AppStrings.homeDeviceConnect,
          onPressed: controller.connect,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Connecting / connected
// ---------------------------------------------------------------------------

class _ConnectingContent extends StatelessWidget {
  const _ConnectingContent({
    required this.connected,
    required this.onCalibrate,
    required this.onSettings,
  });

  final bool connected;
  final VoidCallback onCalibrate;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          connected
              ? 'DEVICE CONNECTED'
              : 'CONNECTING DEVICE',
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeConnectingTitleSize,
            weight: AppTypography.headingWeight,
            color: AppColors.brandBlue,
          ),
        ),

        SizedBox(
          height: AppSpacing.small,
        ),

        if (!connected)
        Text(
          AppStrings.homeConnectingInstruction,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeCardSubtitleSize,
            weight: FontWeight.normal,
            color: AppColors.homeCardText,
          ),
        ),

        SizedBox(
          height: AppSpacing.item,
        ),

        Padding(
          padding: EdgeInsets.all(
            AppSpacing.homeBluetoothImagePadding,
          ),
          child: Image(
            image: AssetImage(
              connected
                ? AppAssets.bluetoothConnected
                : AppAssets.bluetoothUnconnected,
            ),
            width: AppSizes.homeBluetoothImageSize * 1.30,
            height: AppSizes.homeBluetoothImageSize * 1.30,
            fit: BoxFit.contain,
          ),
        ),

        SizedBox(
          height: AppSpacing.item,
        ),

        if (connected) ...<Widget>[
          Text(
            AppStrings.homeConnected,
            style: AppTypography.style(
              size: AppTypography.homeCardTitleSize,
              weight: FontWeight.bold,
              color: AppColors.connected,
            ),
          ),

          SizedBox(
            height: AppSpacing.item,
          ),

          FlatActionButton(
            label: AppStrings.homeManikinCalibration,
            onPressed: onCalibrate,
          ),

          if (AppFeatures.enableDeviceSettings) ...<Widget>[
            SizedBox(
              height: AppSpacing.flowActionStackGap,
            ),

            FlatActionButton(
              label: AppStrings.homeDeviceSettings,
              onPressed: onSettings,
            ),
          ],
        ] else
          const _ScanningLabel(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scanning label
// ---------------------------------------------------------------------------

class _ScanningLabel extends StatefulWidget {
  const _ScanningLabel();

  @override
  State<_ScanningLabel> createState() =>
      _ScanningLabelState();
}

class _ScanningLabelState extends State<_ScanningLabel> {
  Timer? _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(
      AppDurations.homeScanInterval,
      (Timer _) {
        if (!mounted) return;

        setState(() {
          _dots = _dots % 3 + 1;
        });
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${AppStrings.homeScanning}${'.' * _dots}',
      style: AppTypography.style(
        size: AppTypography.homeCardTitleSize,
        weight: FontWeight.bold,
        color: AppColors.brandBlue,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manikin calibration
// ---------------------------------------------------------------------------

Future<void> _openManikinCalibration(
  BuildContext context,
) async {
  DeviceSettings? settings;

  try {
    settings = await AppScope.history(
      context,
    ).loadDeviceSettings();
  } catch (error) {
    debugPrint(
      'Device settings load failed: $error',
    );
  }

  if (!context.mounted) return;

  if (settings?.profile == KinematicProfile.bench) {
    final bool? openSettings = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(
          AppStrings.homeCalibrationRequiresManikinTitle,
        ),
        content: const Text(
          AppStrings.homeCalibrationRequiresManikinBody,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(false),
            child: const Text(
              AppStrings.actionCancel,
            ),
          ),

          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(true),
            child: const Text(
              AppStrings.homeCalibrationRequiresManikinAction,
            ),
          ),
        ],
      ),
    );

    if (openSettings == true && context.mounted) {
      context.pushNamed(
        AppRoutes.deviceSettings,
      );
    }

    return;
  }

  context.pushNamed(
    AppRoutes.manikinCalibration,
  );
}

// ---------------------------------------------------------------------------
// Gradient button
// ---------------------------------------------------------------------------

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: AppSizes.homeButtonHeight,
      ),
      decoration: BoxDecoration(
        gradient: AppGradients.brandVertical,
        borderRadius: BorderRadius.circular(
          AppSizes.homeButtonRadius,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(
            AppSizes.homeButtonRadius,
          ),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal:
                  AppSpacing.homeButtonLabelInsetH,
              vertical:
                  AppSpacing.flowActionLabelInsetV,
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.homeCardTitleSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.homeWelcomeText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}