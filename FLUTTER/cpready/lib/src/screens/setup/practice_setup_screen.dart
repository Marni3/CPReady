/// Practice setup: capture the trainee name that the session is filed under.
///
/// Full-screen (no top header, no bottom nav), like the Step-by-step Guide:
/// a small back arrow beside the title, the big heading, the name field with
/// its helper line, and the Continue button near the bottom.
///
/// This screen drives nothing on the device; the flow is:
/// Setup → Hand Placement → Calibration → countdown → Live Practice.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../widgets/widgets.dart';

/// Practice setup screen.
class PracticeSetupScreen extends StatefulWidget {
  const PracticeSetupScreen({super.key});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _continue() {
    if (!_valid) return;
    context.pushNamed(AppRoutes.handPlacement, extra: _name.text.trim());
  }

  OutlineInputBorder _fieldBorder() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.flowFieldRadius),
      borderSide: const BorderSide(
        color: AppColors.flowPanelBorder,
        width: AppSizes.flowPanelBorderWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceScaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.flowTopPadding,
            bottom: AppSpacing.flowActionBottomPadding,
            left: AppSpacing.page,
            right: AppSpacing.page,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const FlowBackButton(),
                  const SizedBox(width: AppSpacing.flowBackTitleGap),
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
              const SizedBox(height: AppSpacing.flowTitleGap),
              Text(
                AppStrings.setupHeading,
                style: AppTypography.style(
                  size: AppTypography.flowHeadingSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.flowHeadingText,
                ),
              ),
              const SizedBox(height: AppSpacing.flowHeadingGap),
              SizedBox(
                height: AppSizes.flowFieldHeight,
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.flowFieldPaddingH,
                    ),
                    border: _fieldBorder(),
                    enabledBorder: _fieldBorder(),
                    focusedBorder: _fieldBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.flowHelperGap),
              Text(
                AppStrings.setupHelper,
                style: AppTypography.style(
                  size: AppTypography.flowHelperSize,
                  weight: FontWeight.normal,
                  color: AppColors.flowHelperText,
                ),
              ),
              const Spacer(),
              FlatActionButton(
                label: AppStrings.setupContinue,
                onPressed: _valid ? _continue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
