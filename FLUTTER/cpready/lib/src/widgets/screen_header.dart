/// Top bar shared by the tab screens: the brand logo on the left, the
/// "CPREADY" wordmark with the current page label on the right, the Device
/// Settings gear, and a thin grey divider underneath.
///
/// Only the [pageLabel] changes between tabs; every visual value comes from
/// `lib/src/config/`.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/config.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.pageLabel});

  /// Name of the current page, shown underlined beneath the wordmark.
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            page,
            AppSpacing.item,
            page,
            AppSpacing.dividerGap,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Image(
                image: AssetImage(AppAssets.logoBlue),
                width: AppSizes.homeLogoSize,
                height: AppSizes.homeLogoSize,
              ),
              const Spacer(),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    AppStrings.homeHeaderBrand,
                    style: AppTypography.style(
                      size: AppTypography.homeBrandSize,
                      weight: AppTypography.headingWeight,
                      color: AppColors.homeBrandText,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    pageLabel,
                    style:
                        AppTypography.style(
                          size: AppTypography.homePageSize,
                          weight: FontWeight.w500,
                          color: AppColors.homePageText,
                        ).copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.homePageText,
                        ),
                  ),
                ],
              ),
              if (AppFeatures.enableDeviceSettings) ...<Widget>[
                SizedBox(width: AppSpacing.headerSettingsGap),
                IconButton(
                  onPressed: () =>
                      context.pushNamed(AppRoutes.deviceSettings),
                  tooltip: AppStrings.settingsTooltip,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: BoxConstraints.tightFor(
                    width: AppSizes.headerSettingsTapSize,
                    height: AppSizes.headerSettingsTapSize,
                  ),
                  icon: Icon(
                    Icons.settings_rounded,
                    size: AppSizes.iconMedium,
                    color: AppColors.headerSettingsIcon,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: page),
          child: Container(
            height: AppSizes.dividerThickness,
            color: AppColors.divider,
          ),
        ),
      ],
    );
  }
}
