/// Content for the step-by-step guide screen.
///
/// Each step is one sentence: [lead] renders in bold and [body] in the regular
/// weight, so the paragraph reads as a single line of text.

class GuideStep {
  const GuideStep({required this.lead, required this.body});

  /// Bold opening phrase of the step.
  final String lead;

  /// Regular-weight remainder (including the leading space/punctuation).
  final String body;
}

class AppGuideSteps {
  /// The numbered steps, in order.
  static const List<GuideStep> steps = <GuideStep>[
    GuideStep(
      lead: 'Check the surroundings',
      body: ' for any immediate hazards to ensure the scene is completely safe '
          'before approaching the person.',
    ),
    GuideStep(
      lead: 'Tap the person\u2019s shoulders',
      body: ', shout to check for responsiveness, and if there is no response, '
          'immediately activate emergency services and send someone to get an '
          'AED.',
    ),
    GuideStep(
      lead: 'Look for normal breathing',
      body: ' for no more than 10 seconds, remembering that gasping is not '
          'normal. If the person is not breathing normally, start CPR.',
    ),
    GuideStep(
      lead: 'Place the person flat',
      body: ' on their back on a firm, flat surface and kneel closely beside '
          'their chest.',
    ),
    GuideStep(
      lead: 'Place the heel of one hand',
      body: ' on the center of the chest (over the lower half of the '
          'breastbone), interlock your other hand on top, and straighten your '
          'elbows.',
    ),
    GuideStep(
      lead: 'Deliver continuous chest compressions',
      body: ' at a depth of 2 to 2.4 inches (5 to 6 cm) and a rapid rate of '
          '100 to 120 compressions per minute.',
    ),
    GuideStep(
      lead: 'Allow the chest to fully return',
      body: ' to its normal position after every single push, making sure you '
          'do not lean your body weight on the chest.',
    ),
    GuideStep(
      lead: 'Minimize any pauses or interruptions',
      body: ' to keep the blood flowing, only stopping when an AED arrives '
          'or advanced medical responders take over.',
    ),
  ];
}
