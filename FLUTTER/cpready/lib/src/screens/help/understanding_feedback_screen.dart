import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/config.dart';

// ============================================================
// UNDERSTANDING FEEDBACK SCREEN
// ============================================================

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
                // ==================================================
                // HEADER
                // ==================================================

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
                        ).copyWith(height: 1.15),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ==================================================
                // VISUAL INDICATORS / VOICE PROMPTS TABS
                // ==================================================

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

                // ==================================================
                // TAB CONTENT
                // ==================================================

                if (_showVisualIndicators)
                  const _VisualIndicatorsContent()
                else
                  const _VoicePromptsContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FEEDBACK TAB
// ============================================================

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
          constraints: const BoxConstraints(minHeight: 46),
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

// ============================================================
// SHARED INFORMATION CARD STYLE
// ============================================================

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDCE6F1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// VISUAL INDICATORS CONTENT
// ============================================================

class _VisualIndicatorsContent extends StatelessWidget {
  const _VisualIndicatorsContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // UNDERSTANDING THE COLORS
        _ColorGuide(),

        SizedBox(height: 28),

        _SectionHeading(
          title: 'CPR PERFORMANCE INDICATORS',
        ),

        SizedBox(height: 14),

        // ==================================================
        // COMPRESSION DEPTH
        // ==================================================

        _IndicatorCard(
          title: 'Compression Depth',
          description:
              'How far down you push the chest during each compression.',
          rows: [
            _IndicatorRowData(
              value: '< 5 cm',
              label: 'Too Shallow',
              explanation: 'Push deeper.',
              isGood: false,
            ),
            _IndicatorRowData(
              value: '5–6 cm',
              label: 'Within Target',
              explanation: 'Maintain this depth.',
              isGood: true,
            ),
            _IndicatorRowData(
              value: '> 6 cm',
              label: 'Too Deep',
              explanation: 'Reduce how far you push.',
              isGood: false,
            ),
          ],
        ),

        SizedBox(height: 14),

        // ==================================================
        // COMPRESSION RATE
        // ==================================================

        _IndicatorCard(
          title: 'Compression Rate',
          description:
              'How many chest compressions you perform in one minute.',
          rows: [
            _IndicatorRowData(
              value: '< 100 CPM',
              label: 'Too Slow',
              explanation: 'Increase your pace.',
              isGood: false,
            ),
            _IndicatorRowData(
              value: '100–120 CPM',
              label: 'Within Target',
              explanation: 'Maintain a steady rhythm.',
              isGood: true,
            ),
            _IndicatorRowData(
              value: '> 120 CPM',
              label: 'Too Fast',
              explanation: 'Slow down your pace.',
              isGood: false,
            ),
          ],
          footnote: 'CPM means compressions per minute.',
        ),

        SizedBox(height: 14),

        // ==================================================
        // CHEST RECOIL
        // ==================================================

        _IndicatorCard(
          title: 'Chest Recoil',
          description:
              'How well the chest returns to its normal position after each compression.',
          rows: [
            _IndicatorRowData(
              value: '<90% / Partial',
              label: 'Needs Improvement',
              explanation:
                  'Release pressure fully between compressions.',
              isGood: false,
            ),
            _IndicatorRowData(
              value: '≥90% / Full',
              label: 'Meets Target',
              explanation: 'Avoid leaning on the chest.',
              isGood: true,
            ),
          ],
          footnote:
              'Live Practice shows Full or Partial recoil. '
              'Full means complete recoil (100%), while Partial means '
              'incomplete recoil. In Session Summary, an overall recoil '
              'score of 90% or higher meets CPReady’s grading target.',
        ),

        SizedBox(height: 14),

        // ==================================================
        // CHEST COMPRESSION FRACTION
        // ==================================================

        _IndicatorCard(
          title: 'Chest Compression Fraction (CCF)',
          description:
              'The percentage of practice time spent performing chest compressions.',
          rows: [
            _IndicatorRowData(
              value: '< 60%',
              label: 'Below Minimum',
              explanation: 'Reduce unnecessary pauses.',
              isGood: false,
            ),
            _IndicatorRowData(
              value: '≥ 60%',
              label: 'Meets Minimum',
              explanation:
                  'Keep interruptions as short as possible.',
              isGood: true,
            ),
          ],
          footnote:
              'A CCF of at least 60% is a recommended minimum. '
              'Aim for more than 80% when possible.',
        ),

        SizedBox(height: 28),

        // ==================================================
        // ADDITIONAL SESSION INFORMATION
        // ==================================================

        _SectionHeading(
          title: 'ADDITIONAL SESSION INFORMATION',
        ),

        SizedBox(height: 14),

        _AdditionalInformationCard(),

        SizedBox(height: 28),

        // ==================================================
        // BASIS OF CPR STANDARDS
        // ==================================================

        _BasisOfStandardsCard(),
      ],
    );
  }
}

// ============================================================
// UNDERSTANDING THE COLORS
// ============================================================

class _ColorGuide extends StatelessWidget {
  const _ColorGuide();

  @override
  Widget build(BuildContext context) {
    return const _InfoCard(
      title: 'Understanding the Colors',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ColorMeaning(
            color: Color(0xFF238653),
            title: 'Green',
            description: 'The measurement meets the target.',
          ),
          SizedBox(height: 10),
          _ColorMeaning(
            color: Color(0xFFD84A4A),
            title: 'Red',
            description: 'The measurement falls outside the target.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COLOR MEANING ROW
// ============================================================

class _ColorMeaning extends StatelessWidget {
  const _ColorMeaning({
    required this.color,
    required this.title,
    required this.description,
  });

  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title — ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF20344C),
                  ),
                ),
                TextSpan(
                  text: description,
                  style: const TextStyle(
                    color: Color(0xFF506178),
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        color: AppColors.brandBlue,
      ),
    );
  }
}

// ============================================================
// INDICATOR ROW DATA
// ============================================================

class _IndicatorRowData {
  const _IndicatorRowData({
    required this.value,
    required this.label,
    required this.explanation,
    required this.isGood,
  });

  final String value;
  final String label;
  final String explanation;
  final bool isGood;
}

// ============================================================
// INDICATOR CARD
// ============================================================

class _IndicatorCard extends StatelessWidget {
  const _IndicatorCard({
    required this.title,
    required this.description,
    required this.rows,
    this.footnote,
  });

  final String title;
  final String description;
  final List<_IndicatorRowData> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDCE6F1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080E3972),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFF53647A),
            ),
          ),
          const SizedBox(height: 16),

          for (int index = 0; index < rows.length; index++) ...[
            _IndicatorValueRow(data: rows[index]),
            if (index != rows.length - 1)
              const SizedBox(height: 13),
          ],

          if (footnote != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7FC),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                footnote!,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: Color(0xFF596B80),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// INDICATOR VALUE ROW
// ============================================================

class _IndicatorValueRow extends StatelessWidget {
  const _IndicatorValueRow({
    required this.data,
  });

  final _IndicatorRowData data;

  @override
  Widget build(BuildContext context) {
    final Color pillBackground = data.isGood
        ? const Color(0xFFE3F5E9)
        : const Color(0xFFFCE8E8);

    final Color pillText = data.isGood
        ? const Color(0xFF187849)
        : const Color(0xFFBD3535);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          flex: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 95,
              maxWidth: 112,
              minHeight: 42,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pillBackground,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                data.value,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: pillText,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF263B55),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.explanation,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Color(0xFF617187),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ADDITIONAL SESSION INFORMATION
// ============================================================

class _AdditionalInformationCard extends StatelessWidget {
  const _AdditionalInformationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDCE6F1),
        ),
      ),
      child: const Column(
        children: [
          _AdditionalInfoRow(
            icon: Icons.tag_rounded,
            title: 'Compression Counter',
            description:
                'Shows the total number of chest compressions '
                'recorded during practice.',
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              height: 1,
              color: Color(0xFFE5ECF4),
            ),
          ),
          _AdditionalInfoRow(
            icon: Icons.timer_outlined,
            title: 'Session Duration',
            description:
                'Shows how long the practice session lasted, '
                'including pauses.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ADDITIONAL INFORMATION ROW
// ============================================================

class _AdditionalInfoRow extends StatelessWidget {
  const _AdditionalInfoRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FC),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            color: AppColors.brandBlue,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Color(0xFF596B80),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BASIS OF CPR STANDARDS
// ============================================================

class _BasisOfStandardsCard extends StatelessWidget {
  const _BasisOfStandardsCard();

  Future<void> _openAhaResource(BuildContext context) async {
    final Uri url = Uri.parse(
      'https://cpr.heart.org/en/resources/what-is-cpr',
    );

    try {
      final bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open the CPR resource.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open the CPR resource.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Basis of CPR Standards',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CPReady’s CPR performance indicators are based on '
            'the American Heart Association (AHA) 2025 Guidelines '
            'for Cardiopulmonary Resuscitation and Emergency '
            'Cardiovascular Care.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFF53647A),
            ),
          ),

          const SizedBox(height: 12),

          InkWell(
            onTap: () => _openAhaResource(context),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Click here',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: AppColors.brandBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VOICE PROMPTS CONTENT
// ============================================================

class _VoicePromptsContent extends StatelessWidget {
  const _VoicePromptsContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ==================================================
        // INTRODUCTION
        // ==================================================

        _VoicePromptsIntroduction(),

        SizedBox(height: 28),

        _SectionHeading(
          title: 'VOICE COACHING PROMPTS',
        ),

        SizedBox(height: 14),

        // ==================================================
        // TOO FAST
        // ==================================================

        _VoicePromptCard(
          prompt: '“Too fast, slow down.”',
          explanation:
              'Aim for 100–120 chest compressions per minute '
              'while keeping a steady rhythm.',
          isPositive: false,
        ),

        SizedBox(height: 14),

        // ==================================================
        // TOO SLOW
        // ==================================================

        _VoicePromptCard(
          prompt: '“Too slow, compress faster.”',
          explanation:
              'Adult CPR requires a compression rate of '
              '100–120 compressions per minute.',
          isPositive: false,
        ),

        SizedBox(height: 14),

        // ==================================================
        // TOO DEEP
        // ==================================================

        _VoicePromptCard(
          prompt: '“Too deep, adjust your compression depth.”',
          explanation:
              'For adult CPR, avoid compressing the chest '
              'deeper than 6 cm.',
          isPositive: false,
        ),

        SizedBox(height: 14),

        // ==================================================
        // TOO SHALLOW
        // ==================================================

        _VoicePromptCard(
          prompt: '“Too shallow, push deeper.”',
          explanation:
              'For adult CPR, compress the chest to a depth '
              'of at least 5 cm.',
          isPositive: false,
        ),

        SizedBox(height: 14),

        // ==================================================
        // INCOMPLETE RECOIL
        // ==================================================

        _VoicePromptCard(
          prompt:
              '“Incomplete recoil, allow the chest to fully expand.”',
          explanation:
              'The chest should return to its normal position '
              'between compressions. Avoid leaning on it.',
          isPositive: false,
        ),

        SizedBox(height: 14),

        // ==================================================
        // GOOD COMPRESSIONS
        // ==================================================

        _VoicePromptCard(
          prompt: '“Good compressions, keep going!”',
          explanation:
              'CPReady has detected compressions that meet '
              'its feedback criteria. Continue maintaining '
              'your technique.',
          isPositive: true,
        ),

        SizedBox(height: 28),

        // ==================================================
        // VOICE CONTROL
        // ==================================================

        _SectionHeading(
          title: 'VOICE CONTROL',
        ),

        SizedBox(height: 14),

        _VoiceControlCard(),

        SizedBox(height: 20),

        // ==================================================
        // BOTTOM NOTE
        // ==================================================

        _VoicePromptsNote(),
      ],
    );
  }
}

// ============================================================
// VOICE PROMPTS INTRODUCTION
// ============================================================

class _VoicePromptsIntroduction extends StatelessWidget {
  const _VoicePromptsIntroduction();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.flowPanelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.flowPanelBorder,
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.record_voice_over_outlined,
            size: 20,
            color: AppColors.brandBlue,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Understanding Voice Prompts',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'During Live Practice, CPReady provides '
                  'spoken feedback to help you adjust your '
                  'chest compressions.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF53647A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VOICE PROMPT CARD
// ============================================================

class _VoicePromptCard extends StatelessWidget {
  const _VoicePromptCard({
    required this.prompt,
    required this.explanation,
    required this.isPositive,
  });

  final String prompt;
  final String explanation;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final Color promptColor = isPositive
        ? const Color(0xFF188647)
        : const Color(0xFFB82935);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDCE6F1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080E3972),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // SPEAKER ICON
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.volume_up_rounded,
              size: 31,
              color: AppColors.brandBlue,
            ),
          ),

          const SizedBox(width: 14),

          // SPOKEN PROMPT AND EXPLANATION
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prompt,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: promptColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  explanation,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFF596B80),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VOICE CONTROL CARD
// ============================================================

class _VoiceControlCard extends StatelessWidget {
  const _VoiceControlCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDCE6F1),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFEAF2FC),
                borderRadius: BorderRadius.all(
                  Radius.circular(11),
                ),
              ),
              child: Icon(
                Icons.volume_up_outlined,
                color: AppColors.brandBlue,
                size: 20,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable or Disable Voice Coaching',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Use the sound control on the Live Practice '
                  'screen to turn voice prompts on or off.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF596B80),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VOICE PROMPTS BOTTOM NOTE
// ============================================================

class _VoicePromptsNote extends StatelessWidget {
  const _VoicePromptsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.brandBlue,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Voice prompts provide guidance during practice. '
              'They may not play after every compression.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFF596B80),
              ),
            ),
          ),
        ],
      ),
    );
  }
}