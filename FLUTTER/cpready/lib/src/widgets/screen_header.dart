/// Top bar shared by the tab screens: the brand logo on the left, the
/// "CPREADY" wordmark with the current page label on the right, and a thin
/// grey divider underneath.
///
/// Only the [pageLabel] changes between tabs; every visual value comes from
/// `lib/src/config/`.

import 'package:flutter/material.dart';

import '../config/config.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.pageLabel});

  /// Name of the current page, shown underlined beneath the wordmark.
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.item,
            AppSpacing.page,
            AppSpacing.dividerGap,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Image(
                image: AssetImage(AppAssets.logoBlue),
                width: AppSizes.homeLogoSize,
                height: AppSizes.homeLogoSize,
              ),
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
                    style: AppTypography.style(
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.dividerInset,
          ),
          child: Container(
            height: AppSizes.dividerThickness,
            color: AppColors.divider,
          ),
        ),
      ],
    );
  }
}
