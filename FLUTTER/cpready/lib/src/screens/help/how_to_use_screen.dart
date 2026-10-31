import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final double pagePadding = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: pagePadding,
              right: pagePadding,
              top: AppSpacing.guideTopPadding,
              bottom: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // RESPONSIVE HEADER
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AppSpacing.guideBackTapV,
                          horizontal: AppSpacing.guideBackTapRight,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          size: AppSizes.guideBackIconSize,
                          color: AppColors.guideBackIcon,
                        ),
                      ),
                    ),

                    SizedBox(width: AppSpacing.guideBackTitleGap),

                    Expanded(
                      child: Text(
                        'How to Use CPReady',
                        softWrap: true,
                        style: AppTypography.style(
                          size: AppTypography.guideTitleSize,
                          weight: AppTypography.headingWeight,
                          color: AppColors.guideTitleText,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // CONTENT PLACEHOLDER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 36,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.flowPanelBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.flowPanelBorder,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 36,
                        color: AppColors.brandBlue,
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'How to Use CPReady',
                        textAlign: TextAlign.center,
                        style: AppTypography.style(
                          size: 16,
                          weight: FontWeight.bold,
                          color: AppColors.brandBlue,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Instructions will be added soon.',
                        textAlign: TextAlign.center,
                        style: AppTypography.style(
                          size: 13,
                          weight: FontWeight.normal,
                          color: AppColors.homeCardText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}