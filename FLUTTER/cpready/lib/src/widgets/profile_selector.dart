/// Training-mode choice: two tappable rows with a radio indicator.
///
/// The firmware has no way to report which profile it currently stores, so the
/// selector is driven by the app's own state and sends the matching command
/// only when the user changes it.

import 'package:flutter/material.dart';

import '../config/config.dart';
import '../core/ble/kinematic_profile.dart';

/// Selects one of the firmware's two kinematic profiles.
class ProfileSelector extends StatelessWidget {
  const ProfileSelector({
    super.key,
    required this.profile,
    required this.onChanged,
  });

  /// The option currently shown as selected.
  final KinematicProfile profile;

  /// Called when the user taps a different option.
  final ValueChanged<KinematicProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProfileOption(
          title: AppStrings.setupProfileManikin,
          body: AppStrings.setupProfileManikinBody,
          selected: profile == KinematicProfile.manikin,
          onTap: () => onChanged(KinematicProfile.manikin),
        ),
        SizedBox(height: AppSpacing.setupProfileOptionGap),
        _ProfileOption(
          title: AppStrings.setupProfileBench,
          body: AppStrings.setupProfileBenchBody,
          selected: profile == KinematicProfile.bench,
          onTap: () => onChanged(KinematicProfile.bench),
        ),
      ],
    );
  }
}

/// One row of [ProfileSelector].
class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String body;
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
      label: title,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTypography.style(
                        size: AppTypography.profileOptionTitleSize,
                        weight: FontWeight.bold,
                        color: AppColors.profileOptionText,
                      ),
                    ),
                    SizedBox(height: AppSpacing.profileOptionTextGap),
                    Text(
                      body,
                      style: AppTypography.style(
                        size: AppTypography.profileOptionBodySize,
                        weight: FontWeight.normal,
                        color: AppColors.profileOptionBodyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
