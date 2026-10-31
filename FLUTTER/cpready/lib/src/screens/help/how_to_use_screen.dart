import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/config.dart';

// ============================================================
// HOW TO USE CPREADY SCREEN
// ============================================================

class HowToUseScreen extends StatefulWidget {
  const HowToUseScreen({super.key});

  @override
  State<HowToUseScreen> createState() => _HowToUseScreenState();
}

class _HowToUseScreenState extends State<HowToUseScreen> {
  // The first section is expanded when the screen opens.
  int? _expandedSection = 0;

  void _toggleSection(int index) {
    setState(() {
      _expandedSection = _expandedSection == index ? null : index;
    });
  }

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
                        'How to Use CPReady',
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

                const SizedBox(height: 16),

                // ==================================================
                // INTRODUCTION
                // ==================================================

                const Text(
                  'Follow these steps to navigate CPReady '
                  'and complete a practice session.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF596B80),
                  ),
                ),

                const SizedBox(height: 24),

                // ==================================================
                // 01 - CONNECTING TO CPREADY
                // ==================================================

                _GuideSection(
                  number: '01',
                  title: 'Connecting to CPReady',
                  icon: Icons.bluetooth_connected_rounded,
                  expanded: _expandedSection == 0,
                  onTap: () => _toggleSection(0),
                  children: const [
                    _GuideStep(
                      number: '1',
                      title: 'Open the Home Screen',
                      description:
                          'Go to Home to access the device '
                          'connection controls.',
                    ),

                    _GuideStep(
                      number: '2',
                      title: 'Connect Your Device',
                      description:
                          'Make sure Bluetooth is enabled, '
                          'then tap Connect to establish '
                          'a connection with CPReady.',
                    ),

                    _GuideStep(
                      number: '3',
                      title: 'Confirm the Connection',
                      description:
                          'Check the connection status on '
                          'the Home screen before proceeding.',
                      showLine: false,
                    ),

                    SizedBox(height: 16),

                    _GuideRequirement(
                      title: 'Connection Required',
                      description:
                          'An active device connection is '
                          'required for live practice. '
                          'Connect CPReady before starting '
                          'a training session.',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ==================================================
                // 02 - STARTING A PRACTICE SESSION
                // ==================================================

                _GuideSection(
                  number: '02',
                  title: 'Starting a Practice Session',
                  icon: Icons.play_circle_outline_rounded,
                  expanded: _expandedSection == 1,
                  onTap: () => _toggleSection(1),
                  children: const [
                    _GuideStep(
                      number: '1',
                      title: 'Go to Practice',
                      description:
                          'Open the Practice section '
                          'from the app navigation.',
                    ),

                    _GuideStep(
                      number: '2',
                      title: 'Select Start Practice',
                      description:
                          'Tap Start Practice to open '
                          'the Practice Setup screen.',
                    ),

                    _GuideStep(
                      number: '3',
                      title: 'Enter the Trainee Name',
                      description:
                          'Type the name to be used '
                          'for the practice record.',
                    ),

                    _GuideStep(
                      number: '4',
                      title: 'Continue Through Setup',
                      description:
                          'Tap Continue and follow the '
                          'on-screen instructions for '
                          'hand placement and calibration.',
                    ),

                    _GuideStep(
                      number: '5',
                      title: 'Begin Live Practice',
                      description:
                          'Once the device is ready, '
                          'follow the on-screen control '
                          'to begin your session.',
                      showLine: false,
                    ),

                    SizedBox(height: 16),

                    _GuideRequirement(
                      title: 'Before You Continue',
                      description:
                          'The trainee name is required '
                          'to enable Continue. The device '
                          'must also complete calibration '
                          'before live practice begins.',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ==================================================
                // 03 - NAVIGATING LIVE PRACTICE
                // ==================================================

                _GuideSection(
                  number: '03',
                  title: 'Navigating Live Practice',
                  icon: Icons.monitor_heart_outlined,
                  expanded: _expandedSection == 2,
                  onTap: () => _toggleSection(2),
                  children: const [
                    _GuideStep(
                      number: '1',
                      title: 'View Real-Time Feedback',
                      description:
                          'The Live Practice screen displays '
                          'your compression depth, rate, '
                          'and chest recoil readings.',
                    ),

                    _GuideStep(
                      number: '2',
                      title: 'Control Voice Coaching',
                      description:
                          'Tap the sound icon to turn '
                          'spoken feedback on or off.',
                    ),

                    _GuideStep(
                      number: '3',
                      title: 'End Your Session',
                      description:
                          'When you are finished, press '
                          'and hold End Session to '
                          'complete your practice.',
                      showLine: false,
                    ),

                    SizedBox(height: 16),

                    _GuideTip(
                      title: 'Need Help Reading Feedback?',
                      description:
                          'Open Understanding Feedback '
                          'from the Help section to learn '
                          'what the measurements, colors, '
                          'and voice prompts mean.',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ==================================================
                // 04 - VIEWING RESULTS AND HISTORY
                // ==================================================

                _GuideSection(
                  number: '04',
                  title: 'Viewing Results & History',
                  icon: Icons.history_rounded,
                  expanded: _expandedSection == 3,
                  onTap: () => _toggleSection(3),
                  children: const [
                    _GuideStep(
                      number: '1',
                      title: 'View Session Summary',
                      description:
                          'After ending your session, '
                          'review the recorded results '
                          'on the Session Summary screen.',
                    ),

                    _GuideStep(
                      number: '2',
                      title: 'Open History',
                      description:
                          'Go to History from the app '
                          'navigation to view your '
                          'previous practice sessions.',
                    ),

                    _GuideStep(
                      number: '3',
                      title: 'View Session Details',
                      description:
                          'Select a recorded session '
                          'to see its saved results.',
                      showLine: false,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ==================================================
                // IMPORTANT REMINDER
                // ==================================================

                const _ImportantReminder(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EXPANDABLE GUIDE SECTION
// ============================================================

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.number,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onTap,
    required this.children,
  });

  final String number;
  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expanded
              ? const Color(0xFFB7CCE8)
              : const Color(0xFFDCE6F1),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ==================================================
          // SECTION HEADER
          // ==================================================

          Material(
            color: expanded
                ? const Color(0xFFF0F6FE)
                : Colors.white,
            borderRadius: expanded
                ? const BorderRadius.vertical(
                    top: Radius.circular(15),
                  )
                : BorderRadius.circular(15),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(15),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        title,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    Icon(
                      icon,
                      size: 20,
                      color: AppColors.brandBlue,
                    ),

                    const SizedBox(width: 8),

                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 25,
                      color: AppColors.brandBlue,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ==================================================
          // EXPANDED CONTENT
          // ==================================================

          if (expanded) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFFE3EBF5),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// NUMBERED GUIDE STEP
// ============================================================

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
    this.showLine = true,
  });

  final String number;
  final String title;
  final String description;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FC),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFCBDCF2),
                    ),
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),

                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(
                        vertical: 5,
                      ),
                      color: const Color(0xFFDCE7F5),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: showLine ? 22 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF263B55),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    description,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Color(0xFF596B80),
                    ),
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
// REQUIREMENT BOX
// ============================================================

class _GuideRequirement extends StatelessWidget {
  const _GuideRequirement({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: const Color(0xFFF1DEB8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: Color(0xFF9B681D),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF855A1E),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Color(0xFF806B4C),
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
// HELPFUL TIP BOX
// ============================================================

class _GuideTip extends StatelessWidget {
  const _GuideTip({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FE),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: const Color(0xFFD8E6F7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 20,
            color: AppColors.brandBlue,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
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
// IMPORTANT REMINDER
// ============================================================

class _ImportantReminder extends StatelessWidget {
  const _ImportantReminder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.flowPanelBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.flowPanelBorder,
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 21,
            color: AppColors.brandBlue,
          ),

          SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important Reminder',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                  ),
                ),

                SizedBox(height: 8),

                Text(
                  'CPReady is a supplementary CPR training '
                  'tool intended for use with a CPR manikin '
                  'under instructor supervision. It is not '
                  'intended for use on actual patients.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
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