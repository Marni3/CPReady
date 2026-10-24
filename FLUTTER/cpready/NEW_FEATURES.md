# CPReady Flutter — New Features Plan

**Status:** planning only. No application code has been changed for this document.
**Source specification:** `CPReady_Program/docs/NEW_FEATURES_AND_UI_FLOW_GUIDE.md`
**Voice material:** `FLUTTER/app_assets/voice feedback/` (six MP3 files, currently outside the Flutter package)
**Target app:** `FLUTTER/cpready` (Flutter 3.50 pre-release, Android only, portrait locked)

This document audits the app against the firmware features that already exist, defines what
each new feature needs, and sequences the work. Each section ends with the files it touches so
the implementation can be reviewed before any code is written.

---

## 1. What the firmware already supports

Verified in `CPReady_Program`, not just assumed from the guide:

| Capability | Where | Notes |
| :--- | :--- | :--- |
| 12-byte telemetry packet | `include/BLEReadings.h` | `static_assert(sizeof(CPRMetricsPacket) == 12)`; `quality_flags` at byte 11 |
| Quality bitfield | same | `0x01` steady cadence, `0x02` first stroke / after pause, `0x04` bench profile |
| `CALIBRATE`, `START`, `STOP` | `src/main.cpp` | Already used by the app |
| `PAUSE`, `RESUME`, `GET_RESULTS` | `src/main.cpp` | Not used by the app |
| `SET_TIME:<sec>` | `src/main.cpp` | Applies only when `sec > 0`; duration lives in RAM; default 120 s |
| `SET_K:<val>` | `src/main.cpp` | Persists `depth_k` to NVS |
| `SET_PROFILE:BENCH` / `SET_PROFILE:MANIKIN` | `src/main.cpp` | Persists `profile`, and **resets K to that profile's default** (9.5 / 11.2) |
| `CALIBRATE_TARGET:<cm>` | `src/main.cpp` | `K_new = K * target / mean_depth`, valid only inside `1.0..30.0`; needs a FINAL_SUMMARY from the current power cycle |
| `RESET_CONFIG`, `GET_CONFIG` | `src/main.cpp` | Replies go to the ESP32 **serial console**, not BLE |
| Audio cue codes 1..6 | `include/CompressionTracker.h` | Firmware already arbitrates and rate-limits them |
| Auto-stop + FINAL_SUMMARY | `src/main.cpp` | Fires when `elapsed_seconds >= practiceDurationSec` |
| Demo / simulation build | `src/simulation.cpp`, `CPReadyConfig.h` | Separate build; only START/STOP/GET_RESULTS/PAUSE/RESUME/SET_TIME, always `PROMPT_NONE` and `CADENCE_FLAG_STEADY` |

### Firmware arbitration for voice cues (no app logic needed)

| Rule | Value |
| :--- | :--- |
| Minimum gap between any two prompts | 5.0 s (`AUDIO_PROMPT_COOLDOWN_MS`) |
| Error must be sustained for | 3.5 s or 6 consecutive strokes |
| Praise interval | 15 s |
| Priority | recoil > depth (shallow, deep) > rate (slow, fast) > praise |
| Codes | `1` push harder, `2` push shallower, `3` release fully, `4` speed up, `5` slow down, `6` good job |

Because the ESP32 already throttles and arbitrates, the phone only has to turn a non-zero code
into the matching sound once.

---

## 2. Current app baseline

| Firmware feature | Flutter today | Gap |
| :--- | :--- | :--- |
| 12-byte packet | `CprMetrics.fromBytes` reads 11 bytes and ignores byte 11 | `qualityFlags` missing from the model |
| Voice cues | `audioPromptCode` is decoded and `audioPromptText()` exists, but only the unused `widgets/metrics_card.dart` displays it | Nothing is played |
| `SET_PROFILE:*` | Not sent, no selector | No profile concept in the app |
| `CALIBRATE_TARGET:*` | Not sent | No manikin depth calibration; the existing Calibration screen is only the 2 s zero-g baseline |
| `SET_TIME:*` | Never sent; the app relies on the 120 s default | The 15 s calibration trial would change the session length unless restored |
| `PAUSE` / `RESUME` / `GET_RESULTS` | Unused | Out of scope for this plan |
| Quality flags | Absent | No cadence banner, no bench badge |

Relevant existing pieces:

- `lib/src/core/metrics/cpr_metrics.dart` — packet model and cue labels.
- `lib/src/config/ble.dart` — command strings and packet types.
- `lib/src/screens/calibration/calibration_screen.dart` — baseline calibration; Retry now shows only on error.
- `lib/src/screens/begin_compression/begin_compression_screen.dart` — sends `START`.
- `lib/src/screens/live_practice/live_practice_screen.dart` — packet handling, metrics, hold-to-end.
- `lib/src/screens/setup/practice_setup_screen.dart` — trainee name only.
- `lib/src/core/history/session_record.dart`, `lib/src/config/history.dart` — schema v1, summary fields only.
- `lib/src/config/{strings,colors,sizes,spacing,typography,assets}.dart` — all visual values (dims are runtime-scaled through `AppScale`).

---

## 3. Firmware caveats that shape the UI

These are implementation blockers or constraints the app cannot work around:

1. **No BLE acknowledgement for `SET_PROFILE`, `SET_K`, `CALIBRATE_TARGET`.**
   Success is printed to the ESP32 serial console only. The app cannot show the new `K` value
   from the guide's success screen, and cannot distinguish "saved" from "rejected".
   *Options:* (a) show a neutral "Calibration sent" confirmation, (b) add a short BLE reply in
   the firmware (e.g. re-send `PKT_TYPE_CALIB_SUCCESS`), (c) add a new `GET_CONFIG`-style BLE
   query. Recommended: (b) plus (c) before shipping the screen that promises `K`.
2. **`SET_PROFILE` resets the depth scalar.** Selecting a profile overwrites a previously tuned
   `K` for that profile with 11.2 or 9.5. Therefore the app must only send `SET_PROFILE` on an
   explicit user change, never at every session start, and the manikin calibration must run
   *after* the profile is chosen.
3. **`CALIBRATE_TARGET` needs a summary from the same power cycle** (`lastFinalSummary.avg_depth_cm > 0`).
   The 15 s trial must finish and produce `PKT_TYPE_FINAL_SUMMARY` before saving.
4. **`SET_TIME` is RAM-only and global.** The 15 s trial would shorten the next practice run
   unless the app restores the practice duration (120 s) before `START`.
5. **`SET_TIME:0` is ignored** (`sec > 0`), although the guide describes 0 as unlimited.
6. **The simulation build cannot exercise any of this.** It never emits `quality_flags` or
   prompts and has no `CALIBRATE`/`SET_PROFILE`/`CALIBRATE_TARGET` branches. UI work has to be
   verified on the real firmware, or the sim needs extending first.

---

## 4. Feature set and sequence

1. **Packet model** — read the 12th byte with an 11-byte fallback.
2. **Voice coaching** — play the six MP3s on the firmware's cue codes.
3. **Kinematic profile selector** — Manikin / Bench on the Setup screen.
4. **Manikin depth calibration** — 15 s trial, target depth entry, save.
5. **Live practice additions** — cadence warning banner, bench-mode badge.
6. **Persistence (optional)** — store the profile/flags with a session.

Features 1 and 2 are independent and can ship first. 3 and 4 are device-state changes and
should ship together, because profile selection resets `K`. 5 depends on 1.

---

## 5. Feature A — 12-byte telemetry and quality flags

### Model

`lib/src/core/metrics/cpr_metrics.dart`:

- Accept 11 or 12 bytes; when byte 11 is absent, default `qualityFlags = 0x01`
  (steady), matching the guide's compatibility rule.
- Add `qualityFlags` plus getters `isSteadyCadence`, `isFirstStrokeOrPostPause`, `isBenchMode`.
- Update the class doc: "12-byte packet, 11-byte packets accepted from older firmware".
- Keep `packetTypeLabel` and `audioPromptText` as they are.

### Call sites

- `lib/src/core/history/session_record.dart` constructs `CprMetrics` (dummy packet) — add the
  field or keep a defaulted parameter.
- `test/layout_matrix_test.dart` `_summary` — add the field.

### Acceptance

- 11-byte frame decodes with `qualityFlags == 0x01`.
- 12-byte frame decodes bits 0, 1, 2 independently.
- A frame shorter than 11 bytes still throws.

---

## 6. Feature B — Voice coaching

### 6.1 Asset inventory

Source directory: `FLUTTER/app_assets/voice feedback/` (outside the Dart package, so not bundled today).

| Cue code | Firmware constant | Source file | Duration | Suggested asset |
| :---: | :--- | :--- | ---: | :--- |
| 1 | `PROMPT_PUSH_HARDER` | `Compression too shallow.mp3` | 2.43 s | `assets/audio/push_harder.mp3` |
| 2 | `PROMPT_PUSH_LESS` | `Compression too deep.mp3` | 2.85 s | `assets/audio/push_shallower.mp3` |
| 3 | `PROMPT_RELEASE_FULLY` | `Incomplete chest recoil.mp3` | 3.97 s | `assets/audio/release_chest.mp3` |
| 4 | `PROMPT_SPEED_UP` | `Compression rate too slow.mp3` | 2.69 s | `assets/audio/speed_up.mp3` |
| 5 | `PROMPT_SLOW_DOWN` | `Compression rate too fast.mp3` | 2.69 s | `assets/audio/slow_down.mp3` |
| 6 | `PROMPT_GOOD_JOB` | `Correct compressions.mp3` | 2.51 s | `assets/audio/good_compressions.mp3` |

All six are mono 44.1 kHz MP3, 162–184 kbps, ~367 KB total, with no measurable leading silence.
That is small enough to bundle; no download or TTS fallback is needed.

The mapping by filename is unambiguous, but the words should be confirmed by playing each file
once on the device before shipping.

### 6.2 Packaging

- Copy the six files into `FLUTTER/cpready/assets/audio/` with the snake_case names above
  (spaces in asset names are legal but awkward).
- Register the folder in `pubspec.yaml` under `assets:`.
- Add a code → path map to `lib/src/config/assets.dart` so screens never see raw paths, e.g.
  `AppAssets.voicePromptFor(int code)`.

### 6.3 Playback architecture

New `lib/src/core/audio/voice_coach.dart`:

```text
abstract class VoiceCoach {
  Future<void> preload();
  Future<void> play(int cueCode);
  Future<void> stop();
  Future<void> dispose();
}
```

- `AssetVoiceCoach` — production implementation using `audioplayers`.
  One `AudioPlayer` per asset, preloaded with `setSource(AssetSource(path))` when the Live
  screen opens, `ReleaseMode.stop`, `PlayerMode.lowLatency` on Android. On a cue:
  `seek(Duration.zero)` then `resume()`, so the 5 s firmware gap is never spent decoding.
- `SilentVoiceCoach` — no-op used by widget tests and by any environment without audio.
- Inject through `AppScope` (constructor gains a `voiceCoach`), so `LivePracticeScreen` never
  constructs a plugin directly. `CpReadyApp` owns and disposes the real one; test harnesses
  pass `SilentVoiceCoach`.

Android audio context (set once per player):

- `focus: AudioContextConfigFocus.gainTransient` so the cue is heard over the room.
- `respectSilence: false` (a training device should speak even in silent mode; revisit if the
  user disagrees).
- No `stayAwake`.

### 6.4 Trigger rules

In `LivePracticeScreen._onPacket`, after the existing state update:

| Rule | Reason |
| :--- | :--- |
| Only `packetType == 1` (realtime) | Summary/progress packets carry `PROMPT_NONE` |
| Only codes 1..6 | 0 means "nothing to say" |
| Stop after `_ending` / `_finished` | No cue after STOP or auto-stop |
| Ignore the same code within 1 s | Guards against duplicate packets; the firmware's own gap is 5 s |
| Minimum 250 ms between different codes | Prevents overlap if a burst arrives |
| Swallow playback errors and `debugPrint` | Audio failure must never break a session |
| `stop()` on screen dispose/finish | No cue should outlive the session |

The firmware's 5 s cooldown means the app needs no arbitration, priority or praise logic of its
own. The 1 s duplicate guard is deliberately shorter than 5 s so a legitimate repeat still plays.

### 6.5 What the plan does **not** include

- No text-to-speech, no remote audio, no per-cue volume.
- No mute control in v1 (open question 3).

### 6.6 Files

- `lib/src/core/audio/voice_coach.dart` (new)
- `lib/src/config/assets.dart`, `lib/src/config/strings.dart` (cue labels for accessibility)
- `lib/src/core/app_scope.dart`, `lib/main.dart` (injection + lifecycle)
- `lib/src/screens/live_practice/live_practice_screen.dart` (trigger)
- `pubspec.yaml`, `assets/audio/*.mp3` (new assets)

---

## 7. Feature C — Kinematic profile selector

### 7.1 UI

Placement: `Practice Setup`, under the helper line, as a two-option section titled
"Training mode". Both options show the thresholds from the guide so the choice is explicit:

```text
Training mode

(•) Adult Manikin Mode (Recommended)
    Standard AHA thresholds for training manikins.
    Start 0.45 g · Recoil −0.35 g · Depth 5.0–6.0 cm

( ) Hand / Bench Test Mode
    Relaxed sensitivity for desk and palm testing.
    Start 0.25 g · Recoil −0.18 g
```

The Setup screen already scrolls (`AdaptiveScreen`), and the layout matrix test will cover the
added height at 320×568 and at the largest scale.

### 7.2 Commands and state

- New constants in `AppBleConfig`: `commandProfileManikin = 'SET_PROFILE:MANIKIN'`,
  `commandProfileBench = 'SET_PROFILE:BENCH'`.
- Send on an explicit user change only (see caveat 2). Show the selection immediately, send in
  the background, and surface a small "not applied" note if the write throws (screen also
  guards against the device being disconnected).
- The app cannot read the device's stored profile (caveat 1). Options:
  - **Recommended for v1:** keep the selection in memory for the app run, default to Manikin,
    and show the bench badge from live packets once a session starts. No new persistence.
  - Alternative: add `shared_preferences` to remember the last choice across launches; only
    worth it if the user wants the selector to survive a restart.
- Never resend the profile at session start: that would wipe a calibrated `K`.

### 7.3 Files

- `lib/src/config/ble.dart` (commands)
- `lib/src/config/{strings,colors,sizes,spacing,typography}.dart` (labels, selected state)
- `lib/src/screens/setup/practice_setup_screen.dart` (selector)
- a small `lib/src/widgets/profile_selector.dart` (two-option control)

---

## 8. Feature D — Manikin depth calibration

This is separate from the existing baseline Calibration screen. Proposed name everywhere:
**Manikin Calibration** (it sets the depth scalar `K`; the existing one only zeroes the sensor).

### 8.1 Flow

```text
Entry screen            Trial                       Target entry               Result
--------------          --------------------        --------------------       -----------------
Manikin Calibration     15 s countdown              Trial mean depth: 4.40 cm  Calibration sent
30 s guided workflow    live depth while pressing   Manikin reported: [5.2] cm  (or "Saved, K = …"
Start trial  [>]        auto-stops at 15 s          [Cancel] [Save]             once firmware acks)
```

### 8.2 BLE sequence

1. `SET_TIME:15` — shorten the auto-stop for the trial.
2. `CALIBRATE` — wait for `PKT_TYPE_CALIB_SUCCESS` (3). Reuse the baseline screen's error state
   if no success arrives.
3. `START` — trial begins; the screen shows a countdown from `elapsedSeconds` and the live depth.
4. Firmware auto-stops at 15 s and sends `PKT_TYPE_FINAL_SUMMARY` (4). Read `depthCm` as the
   vest mean.
5. User enters the manikin's reported depth (`1.0..10.0` cm, one decimal).
6. `CALIBRATE_TARGET:<value>`.
7. Restore `SET_TIME:120` before leaving the flow (also on cancel), so the next practice run is
   the normal length.

Timeouts: reuse `AppDurations.finalSummaryTimeout` for the summary after an explicit STOP, but
the trial ends on its own — wait up to `15 s + AppDurations.finalSummaryTimeout` and offer a
retry if no summary arrives.

### 8.3 Validation

- Target: numeric, one decimal, `1.0..10.0` cm. Reject empty or non-numeric input.
- Predicted `K` cannot be validated in the app (the current `K` is unknown, caveat 1). If the
  firmware rejects the value (out of `1.0..30.0`), no reply is sent, so the UI must not claim
  success.
- Success copy (pending open question 2):
  - **Without firmware ack:** "Calibration command sent. Verify the depth on the next practice
    run." (no K value)
  - **With a BLE ack:** "Calibration saved to the vest. New scale factor K = …" as the guide shows.

### 8.4 Entry point (open question 1)

Recommended: the connected state of the Home device card gets a secondary text button
"Manikin Calibration" (instructor task, requires a connected device). Alternative: a third card
on the Practice screen — but that screen is trainee-facing and the action changes device
configuration.

### 8.5 Files

- `lib/src/config/app_config.dart` — `AppRoutes.manikinCalibration` (+ `all`).
- `lib/main.dart` — route with `FlowConnectionGuard`.
- `lib/src/screens/manikin_calibration/manikin_calibration_screen.dart` (new).
- `lib/src/config/{strings,colors,sizes,spacing,typography,durations,ble}.dart`.
- `lib/src/widgets/` — reuse `FlatActionButton`, `FlowBackButton`, `FlowIllustrationCard`,
  `ValueCapsule`; add a depth-entry field only if the existing name field style does not fit.

---

## 9. Feature E — Live practice additions

1. **Cadence warning banner** — `isSteadyCadence == false`.
   Bit 0 is also 0 on the first stroke and right after a pause, so showing the banner literally
   would flash it at the start of every run. Proposed rule: show it after **three consecutive
   realtime packets** with `steady == 0` and `firstStroke == 0` (genuine unsteadiness), hide on
   the first steady packet. This app-side smoothing needs sign-off (open question 6).
   Copy: "Rhythm unsteady: depth readings may fluctuate". Placement: above the metric sections,
   full width, amber background, warning color pair added to `AppColors`.
2. **Bench-mode badge** — when `isBenchMode` is true, a small capsule "BENCH MODE" next to the
   session timer, so the user knows strict manikin thresholds are bypassed.
3. **First stroke / post-pause** — the app has no jitter animation; it renders packet values
   directly. Nothing to change. The plan explicitly records this so it is not "fixed" twice.

### Files

- `lib/src/screens/live_practice/live_practice_screen.dart`
- `lib/src/widgets/live_notice_banner.dart` (new) or a the existing capsule pattern
- `lib/src/config/{strings,colors,sizes,spacing,typography,durations}.dart`

---

## 10. Persistence and summary (optional)

Not required by the guide. If the profile should survive in History:

- Add `qualityFlags` (or a derived `benchMode` bool) to `SessionRecord`.
- Bump `AppHistory.schemaVersion` to 2 and add the migration case in
  `lib/src/core/history/session_repository.dart` (`ALTER TABLE … ADD COLUMN`).
- Show "Bench mode" as a caption on the Session Complete screen and the History detail.

Recommended: **defer**. The summary packet already carries the flag, so the result screen can
show it without touching the database.

---

## 11. Configuration additions (all values live in `lib/src/config/`)

| File | New entries |
| :--- | :--- |
| `ble.dart` | `commandPause`, `commandResume`, `commandGetResults`, `commandSetTimePrefix`, `commandProfileManikin`, `commandProfileBench`, `commandCalibrateTargetPrefix`, `commandSetKPrefix` (only the ones used; no speculative constants), `qualityFlagSteady/FirstStroke/Bench` |
| `durations.dart` | `calibrationTrialSeconds = 15`, `practiceDurationSeconds = 120`, `summaryWait` for auto-stop, `voiceDuplicateWindow`, `cadenceWarningPackets = 3` |
| `strings.dart` | Manikin calibration (title, steps, hints, errors), profile section labels/descriptions, cadence warning, bench badge, voice cue labels (already partly present) |
| `colors.dart` | warning background/text, bench badge background/text |
| `sizes.dart` | selector row height/radius, badge height, banner radius/padding |
| `spacing.dart` | selector gaps, banner padding |
| `typography.dart` | selector title/body, badge label, banner text |
| `assets.dart` | `voicePrompts` map (code → asset path) |
| `history.dart` | only if the schema changes |
| `app_config.dart` | new route |

---

## 12. Dependencies

One new runtime dependency is required: audio playback.

| Candidate | Version (Oct 2026) | Verdict |
| :--- | :--- | :--- |
| `audioplayers` | 6.8.1, Flutter ≥ 3.44 | **Recommended.** Local assets, `PlayerMode.lowLatency`, per-player audio context, actively maintained |
| `just_audio` | 0.10.6 | Capable but heavier; its streaming/queue model adds nothing for six short local cues |
| `soundpool` | 2.4.1 | Lowest latency, but a thin, less-maintained plugin; not worth the risk |

Nothing else is needed. `shared_preferences` only if open question 4 chooses persistent profile
state.

---

## 13. Test plan

### Unit

- `CprMetrics.fromBytes`: 11-byte fallback (`0x01`), 12-byte flag combinations, short frame throws.
- `audioPromptText` and the code → asset map cover exactly codes 1..6 and nothing else.
- (If added) warning-smoothing helper: steady/first-stroke/unsteady sequences.

### Widget / layout

- Extend `test/layout_matrix_test.dart` cases with the Manikin Calibration screen (idle, running,
  target entry) and the Setup screen with the profile selector, across the existing
  5 sizes × 4 system font settings + keyboard matrix.
- Cadence banner: absent when steady, absent on the first stroke, present after the third
  unsteady packet, hidden again when steady returns.
- Bench badge: hidden for manikin packets, shown for bench packets.
- Voice: a `SilentVoiceCoach` spy records codes; assert one call per non-zero code, none for 0,
  none after `_ending`, and duplicate suppression inside the window.
- Profile selector: tapping an option sends exactly one command and does not resend on rebuild.

### Manual (real firmware, not the simulation build)

- Each cue file plays: correct words, correct mapping, no leading silence.
- Latency under 5 s cadence: cue starts while compressions continue.
- No cue overlap; no cue after STOP/auto-stop.
- Audio focus does not pause or duck the phone's other audio unexpectedly.
- Profile switch, then manikin calibration, then a practice run: depth matches the manikin.
- Switching profile after calibration resets `K` (expected firmware behavior; confirm the UI
  warns or sequences users correctly).
- `SET_TIME` restored to 120 s after a trial (the next run lasts 2 minutes).
- App restart with the device still calibrated: the device keeps `K`; the app's selector may
  not match (caveat 1) — acceptable for v1.

### Untested / not coverable in CI

- Real BLE writes, audio playback, flash persistence, and the 15 s auto-stop need the device.
- The simulation firmware cannot exercise any new feature.

---

## 14. Phased checklist

### Phase 0 — prerequisites
- [ ] Copy the six MP3s into `assets/audio/`, register the folder in `pubspec.yaml`.
- [ ] Add `audioplayers` and confirm it builds on this Flutter pre-release.
- [ ] Confirm the cue→file mapping by listening to each file.

### Phase 1 — packet model
- [ ] `qualityFlags` + getters + 11-byte fallback in `cpr_metrics.dart`.
- [ ] Update constructor call sites and unit tests.

### Phase 2 — voice coaching
- [ ] `VoiceCoach` interface, `AssetVoiceCoach`, `SilentVoiceCoach`.
- [ ] `AppScope` injection + `CpReadyApp` lifecycle.
- [ ] Live-screen trigger rules and duplicate guard.
- [ ] Spy-based widget test.

### Phase 3 — profile selector
- [ ] Commands + strings/colors/sizes.
- [ ] Selector widget on Setup; send on change only.
- [ ] Matrix test with the new section.

### Phase 4 — manikin calibration
- [ ] Route + screen + `FlowConnectionGuard`.
- [ ] Trial sequence (`SET_TIME:15` → `CALIBRATE` → `START` → summary).
- [ ] Target entry, validation, `CALIBRATE_TARGET`, `SET_TIME` restore.
- [ ] Result state that is honest about the missing BLE ack.
- [ ] Matrix cases + manual device test.

### Phase 5 — live additions
- [ ] Cadence banner with the smoothing rule.
- [ ] Bench badge.
- [ ] Banner/badge widget tests.

### Phase 6 — optional persistence
- [ ] Only if approved: schema v2 + summary caption.

---

## 15. Risks

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| No BLE ack for profile/target/K | UI can lie about success | Neutral copy, or firmware ack before claiming "saved" |
| `SET_PROFILE` resets `K` | A calibrated vest silently returns to 11.2 | Send only on explicit change; document the order (profile → calibrate) |
| `SET_TIME` leaks into the next session | Practice run ends after 15 s | Always restore `SET_TIME:120`, including on cancel |
| Duplicate/late packets | Same cue twice | 1 s same-code guard + firmware 5 s cooldown |
| Audio focus | Cue is muted or ducks music | Explicit `AudioContext`, verified on device |
| 11-byte firmware | Parser crash / missing flags | Length fallback, default steady |
| Simulation build | New UI cannot be demoed | Extend the sim or test on the real device |
| Layout growth on 320×568 | Overflow on Setup/Live | Existing matrix test as the gate |

---

## 16. Open questions

1. **Entry point for Manikin Calibration:** Home device card (recommended) or a third Practice card?
2. **Success confirmation:** accept an honest "command sent" screen, or should the firmware be
   changed to acknowledge `CALIBRATE_TARGET` and report `K` over BLE?
3. **Voice control:** is a mute/speaker toggle required? Should cues play during the 15 s
   calibration trial, where the goal is matching a manikin's depth rather than perfect CPR?
4. **Profile state:** memory-only (default Manikin) or persist the last choice across launches
   (adds `shared_preferences`)?
5. **History:** store the profile/quality flags with a session (schema v2) or leave History as is?
6. **Cadence banner:** the proposed 3-packet smoothing, or show/hide on the literal bit?
7. **Session length:** keep the firmware's 120 s default, or expose a duration choice in Setup?
8. **Audio package:** approve `audioplayers` 6.8.1.

---

## 17. Out of scope

- Firmware changes (acknowledgements, per-profile `K` keys, extending the simulation build).
- Pause/resume UI and `GET_RESULTS` recovery.
- Redesigning the existing baseline Calibration screen, Home, History, or the practice flow.
- Any change outside `FLUTTER/cpready` except copying the voice assets from
  `FLUTTER/app_assets/voice feedback/`.
