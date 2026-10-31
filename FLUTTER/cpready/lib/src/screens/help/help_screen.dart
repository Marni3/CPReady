import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';

import 'about_cpready_screen.dart';
import 'understanding_feedback_screen.dart';
import 'how_to_use_screen.dart';

// ---------------------------------------------------------------------------
// Help & Information
// ---------------------------------------------------------------------------

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final double pagePadding = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return _HelpPageShell(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: pagePadding,
          right: pagePadding,
          top: AppSpacing.guideTopPadding,
          bottom: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER
            _HelpHeader(
              title: 'Help & Information',
              onBack: () => Navigator.of(context).pop(),
            ),

            const SizedBox(height: 32),

            // HOW TO USE CPREADY
            _HelpOption(
              icon: Icons.menu_book_outlined,
              title: 'How to Use CPReady',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HowToUseScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // UNDERSTANDING FEEDBACK
            _HelpOption(
              icon: Icons.bar_chart_outlined,
              title: 'Understanding Feedback',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const UnderstandingFeedbackScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // ABOUT CPREADY
            _HelpOption(
              icon: Icons.info_outline,
              title: 'About CPReady',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutCPReadyScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared white page and status bar
// ---------------------------------------------------------------------------

class _HelpPageShell extends StatelessWidget {
  const _HelpPageShell({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared header
// ---------------------------------------------------------------------------

class _HelpHeader extends StatelessWidget {
  const _HelpHeader({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
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
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.style(
              size: AppTypography.guideTitleSize,
              weight: AppTypography.headingWeight,
              color: AppColors.guideTitleText,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Help menu option
// ---------------------------------------------------------------------------

class _HelpOption extends StatelessWidget {
  const _HelpOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.flowPanelBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.flowPanelBorder,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: AppColors.flowHeadingText,
                size: 26,
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Text(
                  title,
                  style: AppTypography.style(
                    size: AppTypography.flowHelperSize,
                    weight: FontWeight.bold,
                    color: AppColors.flowHeadingText,
                  ),
                ),
              ),

              const Icon(
                Icons.chevron_right,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}



