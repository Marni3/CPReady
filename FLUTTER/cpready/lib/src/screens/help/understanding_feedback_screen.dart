import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';

class UnderstandingFeedbackScreen extends StatefulWidget {
  const UnderstandingFeedbackScreen({super.key});

  @override
  State<UnderstandingFeedbackScreen> createState() =>
      _UnderstandingFeedbackScreenState();
}

class _UnderstandingFeedbackScreenState
    extends State<UnderstandingFeedbackScreen> {
  bool _showVisualIndicators = true;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 5,
                        bottom: AppSpacing.guideBackTapV,
                        right: AppSpacing.guideBackTapRight,
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        size: AppSizes.guideBackIconSize,
                        color: AppColors.guideBackIcon,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      'Understanding Feedback',
                      softWrap: true,
                      style: AppTypography.style(
                        size: AppTypography.guideTitleSize,
                        weight: AppTypography.headingWeight,
                        color: AppColors.guideTitleText,
                      ).copyWith(
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
                const SizedBox(height: 24),

                // VISUAL INDICATORS / VOICE PROMPTS SWITCH
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.flowPanelBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FeedbackTab(
                          title: 'Visual Indicators',
                          selected: _showVisualIndicators,
                          onTap: () {
                            setState(() {
                              _showVisualIndicators = true;
                            });
                          },
                        ),
                      ),

                      const SizedBox(width: 4),

                      Expanded(
                        child: _FeedbackTab(
                          title: 'Voice Prompts',
                          selected: !_showVisualIndicators,
                          onTap: () {
                            setState(() {
                              _showVisualIndicators = false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // PLACEHOLDER CONTENT
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
                        _showVisualIndicators
                            ? Icons.bar_chart_rounded
                            : Icons.record_voice_over_outlined,
                        size: 36,
                        color: AppColors.brandBlue,
                      ),

                      const SizedBox(height: 12),

                      Text(
                        _showVisualIndicators
                            ? 'Visual Indicators'
                            : 'Voice Prompts',
                        textAlign: TextAlign.center,
                        style: AppTypography.style(
                          size: 16,
                          weight: FontWeight.bold,
                          color: AppColors.brandBlue,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Content will be added soon.',
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

// ---------------------------------------------------------------------------
// Switch button
// ---------------------------------------------------------------------------

class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFFD5E4FA)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(
            minHeight: 46,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 12,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: 12,
              weight: selected
                  ? FontWeight.bold
                  : FontWeight.w500,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ),
    );
  }
}