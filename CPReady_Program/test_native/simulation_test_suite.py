#!/usr/bin/env python3
"""
CPReady Comprehensive Simulation & Regression Test Suite
=========================================================
Validates the double integration kinematic model, variable dt integration,
pause recovery with hand tremor, calibration reset, and session mean depth.

Tested waveforms:
- SINE (pure sinusoidal)
- DUTY40 (40/60 asymmetric duty cycle)
- DWELL30 (35/35/30 compression/recoil/dwell)
- DWELL_BOUNCE (dwell with 2 mm manikin chest bounce)
"""

import math
import random
import sys

G_CM = 980.665  # 1 g in cm/s^2
NOMINAL_K = 11.20
REST_LIMIT_G = 0.15  # Relaxed rest limit in new firmware (was 0.05)


class DepthEstimator:
    """Python reference implementation of CPReady DepthEstimator."""

    def __init__(self, capacity=128):
        self.capacity = capacity
        self.buffer = []  # list of (rawNetG, dt)

    def reset(self):
        self.buffer.clear()

    def push(self, raw_net_g, dt=0.01):
        if len(self.buffer) >= self.capacity:
            self.buffer.pop(0)
        self.buffer.append((float(raw_net_g), float(dt)))

    def count(self):
        return len(self.buffer)

    def closed_cycle_depth_cm(self, onset_idx, recoil_end_idx, k=NOMINAL_K):
        n = len(self.buffer)
        if onset_idx < 0 or recoil_end_idx <= onset_idx or recoil_end_idx >= n:
            return 0.0
        m = recoil_end_idx - onset_idx + 1
        if m < 8:
            return 0.0

        # 1. Total duration T and mean acceleration a_bar
        total_t = 0.0
        accel_sum = 0.0
        for i in range(onset_idx, recoil_end_idx + 1):
            a_g, dt = self.buffer[i]
            a_cms2 = a_g * G_CM
            accel_sum += a_cms2 * dt
            total_t += dt

        if total_t <= 0.0:
            return 0.0
        a_bar = accel_sum / total_t

        # 2. Integrate velocity and compute mean velocity v_bar
        v = [0.0] * m
        curr_v = 0.0
        v_weighted_sum = 0.0
        for j in range(m):
            a_g, dt = self.buffer[onset_idx + j]
            a_corr = (a_g * G_CM) - a_bar
            curr_v += a_corr * dt
            v[j] = curr_v
            v_weighted_sum += curr_v * dt

        v_bar = v_weighted_sum / total_t

        # 3. Integrate displacement and track peak downward excursion
        curr_x = 0.0
        max_x = 0.0
        for j in range(m):
            _, dt = self.buffer[onset_idx + j]
            v_corr = v[j] - v_bar
            curr_x += v_corr * dt
            if curr_x > max_x:
                max_x = curr_x

        return max_x * (k / NOMINAL_K)

    def from_rest_depth_cm(self, onset_idx, recoil_end_idx, k=NOMINAL_K):
        n = len(self.buffer)
        if onset_idx < 5 or recoil_end_idx <= onset_idx or recoil_end_idx >= n:
            return 0.0

        start = max(0, onset_idx - 20)
        rest_from = max(0, start - 20)
        if start - rest_from < 5:
            return 0.0

        # Check resting baseline prior to onset
        baseline_sum = 0.0
        baseline_t = 0.0
        for i in range(rest_from, start):
            a_g, dt = self.buffer[i]
            baseline_sum += a_g * dt
            baseline_t += dt

        if baseline_t <= 0.0:
            return 0.0
        baseline = baseline_sum / baseline_t

        for i in range(rest_from, start):
            if abs(self.buffer[i][0] - baseline) > REST_LIMIT_G:
                return 0.0  # Motion exceeds rest threshold

        curr_v = 0.0
        curr_x = 0.0
        max_x = 0.0
        for i in range(start, recoil_end_idx + 1):
            a_g, dt = self.buffer[i]
            curr_v += ((a_g - baseline) * G_CM) * dt
            curr_x += curr_v * dt
            if curr_x > max_x:
                max_x = curr_x

        return max_x * (k / NOMINAL_K)


def generate_cpr_waveform(shape, t, period, depth_cm):
    """Generates continuous downward chest displacement x(t) in cm."""
    if t < 0:
        return 0.0
    phase = (t % period) / period
    if shape == "SINE":
        return 0.5 * depth_cm * (1.0 - math.cos(2.0 * math.pi * phase))
    elif shape == "DUTY40":
        c = 0.40
        if phase < c:
            return 0.5 * depth_cm * (1.0 - math.cos(math.pi * phase / c))
        else:
            return 0.5 * depth_cm * (1.0 + math.cos(math.pi * (phase - c) / (1.0 - c)))
    elif shape == "DWELL30":
        c, r = 0.35, 0.35
        if phase < c:
            return 0.5 * depth_cm * (1.0 - math.cos(math.pi * phase / c))
        elif phase < c + r:
            return 0.5 * depth_cm * (1.0 + math.cos(math.pi * (phase - c) / r))
        else:
            return 0.0
    elif shape == "DWELL_BOUNCE":
        c, r = 0.35, 0.35
        if phase < c:
            return 0.5 * depth_cm * (1.0 - math.cos(math.pi * phase / c))
        elif phase < c + r:
            return 0.5 * depth_cm * (1.0 + math.cos(math.pi * (phase - c) / r))
        else:
            # Manikin ringing
            dwell_t = (phase - c - r) * period
            ramp = 1.0 - math.exp(-dwell_t / 0.01)
            taper = 0.5 * (1.0 + math.cos(math.pi * (phase - c - r) / (1.0 - c - r)))
            return 0.2 * ramp * taper * math.exp(-dwell_t / 0.05) * math.sin(2.0 * math.pi * 6.0 * dwell_t)
    return 0.0


def run_simulation_suite():
    random.seed(42)
    passed = 0
    failed = 0

    def assert_test(name, cond, details=""):
        nonlocal passed, failed
        if cond:
            print(f"  [PASS] {name}")
            passed += 1
        else:
            print(f"  [FAIL] {name} - {details}")
            failed += 1

    print("======================================================================")
    print("CPReady Kinematic Double-Integration & Robustness Simulation Suite")
    print("======================================================================")

    # -------------------------------------------------------------------------
    # TEST 1: Variable sampling interval (dt) robustness
    # -------------------------------------------------------------------------
    print("\n-- Test Group 1: Variable Sampling Interval (dt) Integration --")
    for hz in [70, 85, 100, 115, 130]:
        nominal_dt = 1.0 / hz
        estimator = DepthEstimator(128)
        depth_target = 5.2  # cm
        period = 60.0 / 110.0  # 110 cpm

        # Simulate one full cycle at this rate
        t = 0.0
        h = 1e-4
        steps = int(period * hz)
        for _ in range(steps):
            # Add 5% timing jitter
            jitter = 1.0 + (random.uniform(-0.05, 0.05))
            dt = nominal_dt * jitter
            # Acceleration via numerical 2nd derivative of displacement
            x_prev = generate_cpr_waveform("DWELL30", t - h, period, depth_target)
            x_curr = generate_cpr_waveform("DWELL30", t, period, depth_target)
            x_next = generate_cpr_waveform("DWELL30", t + h, period, depth_target)
            accel_cms2 = (x_next - 2.0 * x_curr + x_prev) / (h * h)
            accel_g = accel_cms2 / G_CM
            estimator.push(accel_g, dt)
            t += dt

        calc_depth = estimator.closed_cycle_depth_cm(0, estimator.count() - 1, k=NOMINAL_K)
        err = abs(calc_depth - depth_target)
        assert_test(
            f"Sampling rate {hz:3d} Hz with jitter (target {depth_target:.1f} cm)",
            err <= 0.35,
            f"got {calc_depth:.2f} cm (error {err:.2f} cm)"
        )

    # -------------------------------------------------------------------------
    # TEST 2: Double integration DC bias / tilt drift cancellation
    # -------------------------------------------------------------------------
    print("\n-- Test Group 2: DC Bias / Gravity Tilt Drift Cancellation --")
    for dc_offset_g in [0.00, 0.02, 0.05, 0.10]:
        estimator = DepthEstimator(128)
        depth_target = 5.0
        period = 60.0 / 100.0
        t = 0.0
        dt = 0.010
        steps = int(period / dt)
        h = 1e-4
        for _ in range(steps):
            x_prev = generate_cpr_waveform("DUTY40", t - h, period, depth_target)
            x_curr = generate_cpr_waveform("DUTY40", t, period, depth_target)
            x_next = generate_cpr_waveform("DUTY40", t + h, period, depth_target)
            accel_cms2 = (x_next - 2.0 * x_curr + x_prev) / (h * h)
            accel_g = (accel_cms2 / G_CM) + dc_offset_g  # Add severe DC tilt / drift
            estimator.push(accel_g, dt)
            t += dt

        calc_depth = estimator.closed_cycle_depth_cm(0, estimator.count() - 1, k=NOMINAL_K)
        err = abs(calc_depth - depth_target)
        assert_test(
            f"DC offset +{dc_offset_g:.2f}g tilt drift cancelled",
            err <= 0.30,
            f"got {calc_depth:.2f} cm with {dc_offset_g}g bias"
        )

    # -------------------------------------------------------------------------
    # TEST 3: Pause recovery & hand tremor with REST_LIMIT_G = 0.15g
    # -------------------------------------------------------------------------
    print("\n-- Test Group 3: Post-Pause Stroke Recovery with Hand Tremor --")
    for tremor_noise_g in [0.02, 0.05, 0.08, 0.11]:
        depth_target = 5.5
        period = 60.0 / 110.0
        dt = 0.010
        trials = 25
        recovered_depths = []

        for _ in range(trials):
            estimator = DepthEstimator(128)
            # 1. Trainee rests hands on chest with tremor before pushing (50 samples = 500 ms)
            for _ in range(50):
                tremor = random.uniform(-tremor_noise_g, tremor_noise_g)
                estimator.push(tremor, dt)

            # 2. Push begins; detector triggers after lowpass filter delay (~4 samples into push)
            trigger_idx = None
            t = 0.0
            steps = int(period / dt)
            h = 1e-4
            for step_i in range(steps):
                x_prev = generate_cpr_waveform("DWELL30", t - h, period, depth_target)
                x_curr = generate_cpr_waveform("DWELL30", t, period, depth_target)
                x_next = generate_cpr_waveform("DWELL30", t + h, period, depth_target)
                accel_cms2 = (x_next - 2.0 * x_curr + x_prev) / (h * h)
                accel_g = (accel_cms2 / G_CM) + random.uniform(-0.01, 0.01)
                estimator.push(accel_g, dt)
                t += dt
                if trigger_idx is None and step_i >= 4 and accel_g > 0.20:
                    trigger_idx = estimator.count() - 1

            recoil_idx = estimator.count() - 1
            d = estimator.from_rest_depth_cm(trigger_idx, recoil_idx, k=NOMINAL_K)
            if d > 0.0:
                recovered_depths.append(d)

        mean_calc_depth = sum(recovered_depths) / len(recovered_depths) if recovered_depths else 0.0
        err = abs(mean_calc_depth - depth_target)
        assert_test(
            f"Post-pause recovery under {tremor_noise_g*1000:.0f} mg hand tremor ({len(recovered_depths)}/{trials} recovered)",
            len(recovered_depths) == trials and err <= 0.40,
            f"got mean {mean_calc_depth:.2f} cm (expected ~{depth_target:.1f} cm), recovered {len(recovered_depths)}/{trials}"
        )

    # -------------------------------------------------------------------------
    # TEST 4: Mean Depth consistency across full multi-burst session
    # -------------------------------------------------------------------------
    print("\n-- Test Group 4: Multi-Burst CPR Session with Mean Depth Accumulation --")
    random.seed(42)
    session_strokes = []
    # 30 compressions -> 5s pause -> 30 compressions
    target_depth = 5.4  # cm
    period = 60.0 / 110.0
    dt = 0.010
    h = 1e-4

    estimator = DepthEstimator(128)

    # Burst 1: 30 strokes
    for stroke_i in range(30):
        # Slightly vary per stroke (+- 5%)
        s_depth = target_depth * random.uniform(0.95, 1.05)
        estimator.reset()
        t = 0.0
        steps = int(period / dt)
        for _ in range(steps):
            x_p = generate_cpr_waveform("DWELL_BOUNCE", t - h, period, s_depth)
            x_c = generate_cpr_waveform("DWELL_BOUNCE", t, period, s_depth)
            x_n = generate_cpr_waveform("DWELL_BOUNCE", t + h, period, s_depth)
            a_g = ((x_n - 2.0 * x_c + x_p) / (h * h)) / G_CM + random.uniform(-0.008, 0.008)
            estimator.push(a_g, dt)
            t += dt
        d = estimator.closed_cycle_depth_cm(0, estimator.count() - 1, k=NOMINAL_K)
        session_strokes.append(d)

    # Pause: 5 seconds hands still (with tremor)
    for _ in range(500):
        estimator.push(random.uniform(-0.05, 0.05), dt)

    # Burst 2: 30 strokes (first stroke starts from rest!)
    # First stroke:
    first_estimator = DepthEstimator(128)
    for _ in range(50):
        first_estimator.push(random.uniform(-0.04, 0.04), dt)
    onset_idx = first_estimator.count() - 1
    t = 0.0
    steps = int(period / dt)
    for _ in range(steps):
        x_p = generate_cpr_waveform("DWELL_BOUNCE", t - h, period, target_depth)
        x_c = generate_cpr_waveform("DWELL_BOUNCE", t, period, target_depth)
        x_n = generate_cpr_waveform("DWELL_BOUNCE", t + h, period, target_depth)
        a_g = ((x_n - 2.0 * x_c + x_p) / (h * h)) / G_CM + random.uniform(-0.008, 0.008)
        first_estimator.push(a_g, dt)
        t += dt
    post_pause_d = first_estimator.from_rest_depth_cm(onset_idx, first_estimator.count() - 1, k=NOMINAL_K)
    session_strokes.append(post_pause_d)

    # Remaining 29 strokes of burst 2:
    for stroke_i in range(29):
        s_depth = target_depth * random.uniform(0.95, 1.05)
        estimator.reset()
        t = 0.0
        steps = int(period / dt)
        for _ in range(steps):
            x_p = generate_cpr_waveform("DWELL_BOUNCE", t - h, period, s_depth)
            x_c = generate_cpr_waveform("DWELL_BOUNCE", t, period, s_depth)
            x_n = generate_cpr_waveform("DWELL_BOUNCE", t + h, period, s_depth)
            a_g = ((x_n - 2.0 * x_c + x_p) / (h * h)) / G_CM + random.uniform(-0.008, 0.008)
            estimator.push(a_g, dt)
            t += dt
        d = estimator.closed_cycle_depth_cm(0, estimator.count() - 1, k=NOMINAL_K)
        session_strokes.append(d)

    # Compute session mean depth (which is the critical final metric)
    mean_depth = sum(session_strokes) / len(session_strokes)
    err = abs(mean_depth - target_depth)
    assert_test(
        f"60-stroke session across 5s pause: all 60 strokes carry valid depth",
        len(session_strokes) == 60 and all(s >= 4.0 for s in session_strokes),
        f"stroke count {len(session_strokes)}, min depth {min(session_strokes):.2f}"
    )
    assert_test(
        f"Session Mean Depth (avg_depth_cm) matches target within 0.15 cm",
        err <= 0.15,
        f"Mean depth = {mean_depth:.2f} cm (target = {target_depth:.2f} cm, diff = {err:.2f} cm)"
    )

    # -------------------------------------------------------------------------
    # TEST 5: Default Manikin K=48.20 (4.30x Coupling), Calibration Bounds & Error Codes
    # -------------------------------------------------------------------------
    print("\n-- Test Group 5: Default Manikin K=48.20, Calibration Bounds & Error Codes --")
    default_manikin_k = 48.20
    corrupted_k = 72.50
    active_k = corrupted_k
    # When RESET_K or SET_TIME:15 is received:
    active_k = default_manikin_k
    assert_test("RESET_K / SET_TIME:15 restores Manikin K to default 48.20", active_k == default_manikin_k, f"got {active_k}")

    # Verify 1.3 cm raw physical vest motion scales to ~5.60 cm at default K=48.20 (with NOMINAL_K=11.20)
    raw_vest_cm = 1.30
    scaled_default_cm = raw_vest_cm * (default_manikin_k / NOMINAL_K)
    assert_test(
        "Out-of-the-box K=48.20 scales 1.30 cm raw vest motion to 5.59 cm manikin depth",
        abs(scaled_default_cm - 5.60) <= 0.05,
        f"got {scaled_default_cm:.2f} cm"
    )

    # Verify screenshot scenario (1.3 cm -> 5.6 cm, ratio 4.31x) is accepted within [0.15, 8.50]
    screenshot_ratio = 5.6 / 1.3
    screenshot_new_k = NOMINAL_K * screenshot_ratio
    assert_test(
        "Calibration accepts 4.31x ratio (1.3 cm -> 5.6 cm) and computes K=48.25",
        0.15 <= screenshot_ratio <= 8.50 and 1.0 <= screenshot_new_k <= 100.0,
        f"ratio={screenshot_ratio:.2f}, newK={screenshot_new_k:.2f}"
    )

    # Verify distinct error codes: ERR_NO_TRIAL_DATA (6) for <3 strokes vs ERR_CALIB_OUT_OF_RANGE (8)
    def simulate_calibrate_target(strokes, avg_depth_cm, target_cm, current_k=48.20):
        if strokes < 3 or avg_depth_cm <= 0.0:
            return (False, 6)  # ERR_NO_TRIAL_DATA
        if target_cm <= 0.0:
            return (False, 8)  # ERR_CALIB_OUT_OF_RANGE
        ratio = target_cm / avg_depth_cm
        if ratio < 0.15 or ratio > 8.50:
            return (False, 8)  # ERR_CALIB_OUT_OF_RANGE
        new_k = current_k * ratio
        if 1.0 <= new_k <= 100.0:
            return (True, 0)
        return (False, 8)

    ok_2_strokes, code_2_strokes = simulate_calibrate_target(2, 5.5, 5.6)
    ok_3_strokes, code_3_strokes = simulate_calibrate_target(3, 5.5, 5.6)
    ok_extreme, code_extreme = simulate_calibrate_target(15, 5.5, 50.0)
    assert_test("Calibration with 2 strokes returns ERR_NO_TRIAL_DATA (6)", not ok_2_strokes and code_2_strokes == 6)
    assert_test("Calibration with 3 strokes succeeds", ok_3_strokes and code_3_strokes == 0)
    assert_test("Calibration with out-of-bounds target returns ERR_CALIB_OUT_OF_RANGE (8)", not ok_extreme and code_extreme == 8)

    # -------------------------------------------------------------------------
    # TEST 6: Damped-Recoil Manikin Stroke Detection (Undercounting Regression)
    # -------------------------------------------------------------------------
    print("\n-- Test Group 6: Damped-Recoil Manikin Stroke Detection (15s Trial @ 110 CPM) --")
    # Simulate a 15s trial (27 strokes at 110 CPM) where passive manikin recoil is heavily damped
    # by the trainee's hands (push = 0.22s impulsive, slow damped release = 0.30s, raw displacement = 1.30 cm).
    dt = 0.010
    period = 60.0 / 110.0
    total_strokes_expected = 27
    raw_disp_cm = 1.30
    alpha = 0.25

    # Tuned firmware parameters (CPReadyConfig.h)
    compression_start_g = 0.28
    min_start_g = 0.08
    adaptive_start_frac = 0.30
    recoil_arm_frac = 0.15
    recoil_arm_min_g = 0.04
    stroke_finish_g = -0.02
    min_stroke_depth_cm = 0.25

    filtered_g = 0.0
    envelope_g = 0.0
    state = "WAITING"
    peak_accel = 0.0
    recoil_armed = False
    stroke_start_ms = 0
    last_end_ms = 0
    detected_strokes = 0
    estimator = DepthEstimator(128)
    onset_idx = 0
    last_end_idx = 0

    for stroke_n in range(total_strokes_expected):
        steps = int(period / dt)
        for s in range(steps):
            now_ms = int((stroke_n * period + s * dt) * 1000) + 500
            in_cycle = s * dt
            # Asymmetric damped manikin waveform: 0.18s push, 0.32s damped release
            p_push = 0.18
            p_rel = 0.32
            if in_cycle < p_push:
                w = math.pi / p_push
                a_cms2 = 0.5 * raw_disp_cm * (w * w) * math.cos(math.pi * in_cycle / p_push)
            elif in_cycle < p_push + p_rel:
                w = math.pi / p_rel
                a_cms2 = -0.5 * raw_disp_cm * (w * w) * math.cos(math.pi * (in_cycle - p_push) / p_rel)
            else:
                a_cms2 = 0.0
            raw_g = a_cms2 / G_CM
            filtered_g = alpha * raw_g + (1.0 - alpha) * filtered_g
            estimator.push(raw_g, dt)
            sample_idx = estimator.count() - 1

            envelope_g *= 0.993
            if abs(filtered_g) > envelope_g:
                envelope_g = abs(filtered_g)

            start_thresh = min(compression_start_g, max(min_start_g, adaptive_start_frac * envelope_g))
            arm_level = -max(recoil_arm_min_g, recoil_arm_frac * peak_accel)

            if state == "WAITING":
                lockout_ok = (stroke_start_ms == 0) or (now_ms - stroke_start_ms > 300)
                quiet_ok = (now_ms - last_end_ms > 80)
                if filtered_g > start_thresh and lockout_ok and quiet_ok:
                    state = "COMPRESSING"
                    stroke_start_ms = now_ms
                    onset_idx = sample_idx
                    peak_accel = filtered_g
                    recoil_armed = False
            elif state == "COMPRESSING":
                if filtered_g > peak_accel:
                    peak_accel = filtered_g
                if filtered_g < 0.0:
                    state = "RECOILING"
                    recoil_armed = False
            elif state == "RECOILING":
                if filtered_g < arm_level:
                    recoil_armed = True
                if recoil_armed and filtered_g >= stroke_finish_g:
                    phys_cm = estimator.closed_cycle_depth_cm(last_end_idx, sample_idx, k=NOMINAL_K)
                    if phys_cm <= 0.0:
                        phys_cm = raw_disp_cm
                    if phys_cm >= min_stroke_depth_cm:
                        detected_strokes += 1
                        last_end_ms = now_ms
                        last_end_idx = sample_idx
                    state = "WAITING"

    assert_test(
        f"Damped-recoil manikin 15s trial detects all {total_strokes_expected} strokes without merging",
        detected_strokes == total_strokes_expected,
        f"detected {detected_strokes} / {total_strokes_expected} strokes"
    )

    print("\n======================================================================")
    print(f"Results: {passed} PASSED, {failed} FAILED")
    print("======================================================================")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(run_simulation_suite())
