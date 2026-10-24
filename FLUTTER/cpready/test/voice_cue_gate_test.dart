/// Cue gating: unknown codes are ignored, duplicates are dropped, and two
/// different cues never start on top of each other.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/core/audio/voice_cue_gate.dart';

void main() {
  test('plays a real cue once and drops an immediate duplicate', () {
    DateTime now = DateTime(2026, 10, 25, 12);
    final VoiceCueGate gate = VoiceCueGate(clock: () => now);

    expect(gate.allows(0), isFalse, reason: '0 means "nothing to say"');
    expect(gate.allows(7), isFalse, reason: 'no asset for this code');

    expect(gate.allows(1), isTrue);
    now = now.add(const Duration(milliseconds: 500));
    expect(gate.allows(1), isFalse);

    now = now.add(const Duration(milliseconds: 600));
    expect(
      gate.allows(1),
      isTrue,
      reason: 'the duplicate window is one second',
    );
  });

  test('leaves the minimum gap between different cues', () {
    DateTime now = DateTime(2026, 10, 25, 12);
    final VoiceCueGate gate = VoiceCueGate(clock: () => now);

    expect(gate.allows(1), isTrue);
    now = now.add(const Duration(milliseconds: 100));
    expect(gate.allows(2), isFalse);

    now = now.add(const Duration(milliseconds: 200));
    expect(gate.allows(2), isTrue);
  });

  test('a new session can start with any cue', () {
    DateTime now = DateTime(2026, 10, 25, 12);
    final VoiceCueGate gate = VoiceCueGate(clock: () => now);

    expect(gate.allows(1), isTrue);
    gate.reset();
    expect(gate.allows(1), isTrue);
  });
}
