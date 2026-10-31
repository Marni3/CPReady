import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';

// ---------------------------------------------------------------------------
// About CPReady
// ---------------------------------------------------------------------------

class AboutCPReadyScreen extends StatelessWidget {
  const AboutCPReadyScreen({super.key});

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
              title: 'About CPReady',
              onBack: () => Navigator.of(context).pop(),
            ),

            const SizedBox(height: 24),

            // LOGO AND VERSION CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: AppColors.flowPanelBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // CPR illustration
                     // CPR illustration
                      Transform.translate(
                        offset: const Offset(0, 8),
                        child: Image.asset(
                          AppAssets.logoBlue,
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                        ),
                      ),

                      const SizedBox(width: 10),

                      // CPREADY wordmark and ECG
                      // Both moved 8 pixels downward
                      Transform.translate(
                        offset: const Offset(0, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CPREADY',
                              style: AppTypography.style(
                                size: 23,
                                weight: FontWeight.w800,
                                color: AppColors.brandBlue,
                              ),
                            ),

                            // ECG directly underneath CPREADY
                            Transform.translate(
                              offset: const Offset(0, -9),
                              child: SizedBox(
                                width: 180,
                                height: 40,
                                child: CustomPaint(
                                  painter: _ECGLinePainter(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Gap below logo
                  const SizedBox(height: 4),

                  Text(
                    'Version 1.0.0',
                    textAlign: TextAlign.center,
                    style: AppTypography.style(
                      size: 12,
                      weight: FontWeight.normal,
                      color: AppColors.homeCardText,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ABOUT THE APPLICATION
            const _AboutSectionHeading(
              title: 'About the Application',
            ),

            const SizedBox(height: 10),

            Text(
              AppStrings.homeInfoBody,
              textAlign: TextAlign.left,
              style: AppTypography.style(
                size: 12.5,
                weight: FontWeight.normal,
                color: AppColors.homeCardText,
              ).copyWith(
                height: 1.5,
              ),
            ),

            const SizedBox(height: 22),

            // DEVELOPED BY
            const _AboutSectionHeading(
              title: 'Developed by',
            ),

            const SizedBox(height: 8),

            Text(
              'Bataan National High School – Senior High School (BNHS-SHS)\n'
              'Science, Technology, Engineering, and Mathematics (STEM) Health-Allied\n'
              'Research I and II\n'
              'Group 6 – NONAGON\n'
              'A.Y. 2026–2027',
              textAlign: TextAlign.left,
              style: AppTypography.style(
                size: 12.5,
                weight: FontWeight.normal,
                color: AppColors.homeCardText,
              ).copyWith(
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// White page and status bar
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
// Back button and page title
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
// About page section headings
// ---------------------------------------------------------------------------

class _AboutSectionHeading extends StatelessWidget {
  const _AboutSectionHeading({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.style(
        size: 16,
        weight: FontWeight.bold,
        color: AppColors.brandBlue,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ECG line beneath CPREADY
// ---------------------------------------------------------------------------

class _ECGLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brandBlue
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    final double mid = size.height * 0.50;

    // Long straight baseline
    path.moveTo(0, mid);
    path.lineTo(size.width * 0.76, mid);

    // Small upward movement
    path.lineTo(size.width * 0.785, mid - 4);

    // Small downward movement
    path.lineTo(size.width * 0.81, mid + 5);

    // Main tall upward spike
    path.lineTo(size.width * 0.845, mid - 18);

    // Deep downward spike
    path.lineTo(size.width * 0.875, mid + 18);

    // Smaller upward recovery
    path.lineTo(size.width * 0.905, mid - 6);

    // Return to baseline
    path.lineTo(size.width * 0.935, mid);

    // Short ending baseline
    path.lineTo(size.width, mid);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}