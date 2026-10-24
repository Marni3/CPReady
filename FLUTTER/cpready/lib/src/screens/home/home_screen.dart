/// Tab 1 — Home.
///
/// Layout: header (small logo + "CPREADY"/"Home" + a thin black divider), a
/// gradient welcome card, the device-connection card, and a dotted info card.
///
/// Every visual value (colors, sizes, spacing, strings, durations) comes from
/// `lib/src/config/`; this file only composes widgets.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/ble/ble_controller.dart';
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
          ScreenHeader(pageLabel: AppStrings.homeHeaderPage),
          Expanded(
            child: ContentBounds(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: page),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const _WelcomeCard(),
                          SizedBox(height: AppSpacing.homeSectionGap),
                          _DeviceCard(controller: controller),
                          SizedBox(height: AppSpacing.homeSectionGap),
                          const _InfoCard(),
                        ],
                      ),
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

/// Gradient banner: left-aligned "Welcome!" with "Start your training now"
/// scaled to occupy exactly the same width on a single line.
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

    // Size the subtitle so its single-line width matches "Welcome!" exactly.
    final double titleWidth = _measure(AppStrings.homeWelcomeTitle, titleStyle);
    final double subtitleWidth = _measure(
      AppStrings.homeWelcomeSubtitle,
      subtitleStyle,
    );
    final double subtitleSize =
        AppTypography.homeWelcomeSubtitleSize * (titleWidth / subtitleWidth);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: AppSizes.homeWelcomeCardMinHeight),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(
        left: AppSpacing.homeWelcomeInset,
        right: AppSpacing.homeCardPadding,
        top: AppSpacing.homeCardPadding,
        bottom: AppSpacing.homeCardPadding,
      ),
      decoration: BoxDecoration(
        gradient: AppGradients.brandVertical,
        borderRadius: BorderRadius.circular(AppSizes.homeCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(AppStrings.homeWelcomeTitle, style: titleStyle),
          SizedBox(height: AppSpacing.homeWelcomeGap),
          Text(
            AppStrings.homeWelcomeSubtitle,
            maxLines: 1,
            softWrap: false,
            style: subtitleStyle.copyWith(fontSize: subtitleSize),
          ),
        ],
      ),
    );
  }

  /// Width of [text] rendered on a single line with [style].
  static double _measure(String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }
}

// ---------------------------------------------------------------------------
// Device card
// ---------------------------------------------------------------------------

/// White card with a brand-blue border that reflects the BLE connection state.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final bool connected = controller.isConnected;
        final bool busy = controller.isBusy;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSpacing.homeCardPadding),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppSizes.homeCardRadius),
            border: Border.all(
              color: AppColors.homeCardBorder,
              width: AppSizes.homeCardBorderWidth,
            ),
          ),
          child: (busy || connected)
              ? _ConnectingContent(
                  connected: connected,
                  onCalibrate: () =>
                      context.pushNamed(AppRoutes.manikinCalibration),
                )
              : _NotConnectedContent(controller: controller),
        );
      },
    );
  }
}

/// Nothing paired yet: illustration, prompt, and the connect button.
class _NotConnectedContent extends StatelessWidget {
  const _NotConnectedContent({required this.controller});

  final BleController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(AppSpacing.homeBluetoothImagePadding),
          child: Image(
            image: AssetImage(AppAssets.bluetoothUnconnected),
            width: AppSizes.homeBluetoothImageSize,
            height: AppSizes.homeBluetoothImageSize,
          ),
        ),
        SizedBox(height: AppSpacing.item),
        Text(
          AppStrings.homeDeviceNoneTitle,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeCardTitleSize,
            weight: FontWeight.bold,
            color: AppColors.homeCardText,
          ),
        ),
        SizedBox(height: AppSpacing.small),
        Text(
          AppStrings.homeDeviceNoneSubtitle,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeCardSubtitleSize,
            weight: FontWeight.normal,
            color: AppColors.homeCardText,
          ),
        ),
        SizedBox(height: AppSpacing.item),
        _GradientButton(
          label: AppStrings.homeDeviceConnect,
          onPressed: controller.connect,
        ),
      ],
    );
  }
}

/// Connecting / connected: title, instructions, illustration, status label,
/// and — once connected — the manikin calibration entry point.
class _ConnectingContent extends StatelessWidget {
  const _ConnectingContent({
    required this.connected,
    required this.onCalibrate,
  });

  final bool connected;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          AppStrings.homeConnectingTitle,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeConnectingTitleSize,
            weight: AppTypography.headingWeight,
            color: AppColors.brandBlue,
          ),
        ),
        SizedBox(height: AppSpacing.small),
        Text(
          AppStrings.homeConnectingInstruction,
          textAlign: TextAlign.center,
          style: AppTypography.style(
            size: AppTypography.homeCardSubtitleSize,
            weight: FontWeight.normal,
            color: AppColors.homeCardText,
          ),
        ),
        SizedBox(height: AppSpacing.item),
        Padding(
          padding: EdgeInsets.all(AppSpacing.homeBluetoothImagePadding),
          child: Image(
            image: AssetImage(AppAssets.bluetoothConnected),
            width: AppSizes.homeBluetoothImageSize,
            height: AppSizes.homeBluetoothImageSize,
          ),
        ),
        SizedBox(height: AppSpacing.item),
        if (connected) ...<Widget>[
          Text(
            AppStrings.homeConnected,
            style: AppTypography.style(
              size: AppTypography.homeCardTitleSize,
              weight: FontWeight.bold,
              color: AppColors.connected,
            ),
          ),
          SizedBox(height: AppSpacing.item),
          FlatActionButton(
            label: AppStrings.homeManikinCalibration,
            onPressed: onCalibrate,
          ),
        ] else
          const _ScanningLabel(),
      ],
    );
  }
}

/// "Scanning." → "Scanning.." → "Scanning..." on a repeat.
class _ScanningLabel extends StatefulWidget {
  const _ScanningLabel();

  @override
  State<_ScanningLabel> createState() => _ScanningLabelState();
}

class _ScanningLabelState extends State<_ScanningLabel> {
  Timer? _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(AppDurations.homeScanInterval, (Timer _) {
      if (!mounted) return;
      setState(() => _dots = _dots % 3 + 1);
    });
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
// Info card
// ---------------------------------------------------------------------------

/// White card with a brand-blue dashed border and the CPReady blurb.
class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return DottedBorder(
      color: AppColors.homeCardBorder,
      strokeWidth: AppSizes.homeCardBorderWidth,
      radius: AppSizes.homeCardRadius,
      dash: AppSizes.homeDottedDash,
      gap: AppSizes.homeDottedGap,
      padding: EdgeInsets.all(AppSpacing.homeCardPadding),
      child: Text(
        AppStrings.homeInfoBody,
        textAlign: TextAlign.center,
        style: AppTypography.style(
          size: AppTypography.homeInfoSize,
          weight: FontWeight.normal,
          color: AppColors.homeCardText,
          height: 1.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// Full-width brand-gradient button with white bold text.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: AppSizes.homeButtonHeight),
      decoration: BoxDecoration(
        gradient: AppGradients.brandVertical,
        borderRadius: BorderRadius.circular(AppSizes.homeButtonRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.homeButtonRadius),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.homeButtonLabelInsetH,
              vertical: AppSpacing.flowActionLabelInsetV,
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
