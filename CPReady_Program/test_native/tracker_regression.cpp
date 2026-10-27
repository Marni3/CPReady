// Native regression test for CompressionTracker (no ESP32 needed).
//
// Builds the production headers against shim/Arduino.h and drives the tracker with
// chest displacement waveforms whose depth, rate and pauses are known. Each check
// prints PASS/FAIL; the exit code is the number of failures.
//
// Build (from this folder):
//   g++ -std=c++17 -O2 -I shim -I ../include tracker_regression.cpp -o tracker_regression
//   ./tracker_regression

#include <cstdio>
#include <cmath>
#include <vector>
#include <algorithm>
#include <initializer_list>
#include "CompressionTracker.h"
#include "GravityAxis.h"

static const double G_CM = 980.665;
static const double PI_D = 3.14159265358979323846;
static int failures = 0;

static void check(bool ok, const char* what, double got, double lo, double hi) {
    printf("[%s] %-66s got %8.2f  (expected %.2f .. %.2f)\n", ok ? "PASS" : "FAIL", what, got, lo, hi);
    if (!ok) failures++;
}

static void checkNear(const char* what, double got, double want, double tol) {
    check(fabs(got - want) <= tol, what, got, want - tol, want + tol);
}

struct Gauss {
    unsigned long long s;
    explicit Gauss(unsigned seed) : s(seed * 2654435761ull + 1) {}
    double uni() { s = s * 6364136223846793005ull + 1442695040888963407ull; return ((s >> 11) + 0.5) / 9007199254740992.0; }
    double operator()() { double a = uni(), b = uni(); return sqrt(-2.0 * log(a)) * cos(2.0 * PI_D * b); }
};

enum Shape { SINE, DUTY40, DWELL30, DWELL_BOUNCE, DWELL_STRONG_BOUNCE };

static const char* shapeName(Shape s) {
    switch (s) {
        case SINE: return "sine";
        case DUTY40: return "40/60 duty";
        case DWELL30: return "35/35/30 dwell";
        case DWELL_BOUNCE: return "dwell + 2 mm bounce";
        default: return "dwell + 4 mm bounce";
    }
}

// Downward chest displacement (cm) at cycle phase u in [0,1).
static double displacement(Shape shape, double u, double T, double D) {
    switch (shape) {
        case SINE:
            return 0.5 * D * (1.0 - cos(2.0 * PI_D * u));
        case DUTY40: {
            const double c = 0.40;
            if (u < c) return 0.5 * D * (1.0 - cos(PI_D * u / c));
            return 0.5 * D * (1.0 + cos(PI_D * (u - c) / (1.0 - c)));
        }
        case DWELL30:
        case DWELL_BOUNCE:
        case DWELL_STRONG_BOUNCE: {
            const double c = 0.35, r = 0.35;
            if (u < c) return 0.5 * D * (1.0 - cos(PI_D * u / c));
            if (u < c + r) return 0.5 * D * (1.0 + cos(PI_D * (u - c) / r));
            if (shape == DWELL30) return 0.0;
            // The manikin spring rings once the chest reaches the top. The (1 - e^-t/10ms)
            // ramp starts the ring with zero velocity and the cosine taper ends it with zero
            // displacement and velocity before the next push, so the synthetic waveform has
            // no steps (a step would be an unphysical acceleration impulse).
            double t = (u - c - r) * T;
            double ramp = 1.0 - exp(-t / 0.01);
            double taper = 0.5 * (1.0 + cos(PI_D * (u - c - r) / (1.0 - c - r)));
            if (shape == DWELL_BOUNCE) return 0.2 * ramp * taper * exp(-t / 0.05) * sin(2.0 * PI_D * 6.0 * t);
            return 0.4 * ramp * taper * exp(-t / 0.06) * sin(2.0 * PI_D * 8.0 * t);
        }
    }
    return 0.0;
}

// One stretch of the session. cpm = 0 means hands still; a still stretch may contain
// one short bump (hands knocked or repositioned) of bumpCm, centred in the stretch.
struct Segment {
    double seconds;
    double cpm;
    double depthCm;
    double bumpCm = 0.0;
};

struct Options {
    double noiseG = 0.005;   // Sensor noise (1 sigma)
    double offsetG = 0.0;    // Constant error left after calibration (drift, tilt)
    float k = 0.0f;          // Depth K; 0 keeps the profile default
};

struct Run {
    int detected = 0;
    int expected = 0;
    std::vector<float> rates;          // rates of strokes carrying a cadence
    std::vector<float> depths;         // depths of strokes carrying a cadence
    std::vector<float> allDepths;      // every reported depth, in order
    std::vector<float> firstDepths;    // depths of first / post-pause strokes
    int zeroRatePostPause = 0;         // post-pause strokes reporting rate 0
    int postPauseStrokes = 0;
    uint8_t lastFlags = 0;
    float finalCcf = 0.0f;
    uint32_t finalElapsed = 0;
    CPRSessionSummary summary;
};

// Feeds a displacement function x(t) (cm, downward) through the tracker at 100 Hz,
// with the production EMA on the detection input and the raw signal for depth.
template <typename XFn>
static Run feed(XFn x, double seconds, CPReadyConfig::KinematicProfile profile, unsigned seed,
                const Options& opt) {
    CompressionTracker tracker;
    tracker.setProfile(profile);
    if (opt.k > 0.0f) tracker.setDepthK(opt.k);
    const uint32_t t0 = 5000;
    tracker.startSession(t0);

    Gauss noise(seed);
    const double fs = 100.0, h = 1e-4;
    float ema = 0.0f;
    Run run;
    const int n = (int)llround(seconds * fs);
    for (int i = 0; i < n; i++) {
        const double t = i / fs;
        const double a = (x(t + h) - 2.0 * x(t) + x(t - h)) / (h * h);
        float net = (float)(a / G_CM + opt.offsetG + opt.noiseG * noise());
        ema = 0.25f * net + 0.75f * ema;
        uint32_t ms = t0 + (uint32_t)llround(t * 1000.0);
        if (tracker.processSample(ema, net, ms)) {
            const CPRReading& r = tracker.getReading();
            run.detected++;
            run.lastFlags = r.quality_flags;
            run.allDepths.push_back(r.depth_cm);
            if (r.quality_flags & CADENCE_FLAG_FIRST_STROKE) {
                run.postPauseStrokes++;
                run.firstDepths.push_back(r.depth_cm);
                if (r.rate_cpm == 0.0f) run.zeroRatePostPause++;
            } else if (r.rate_cpm > 0.0f) {
                run.rates.push_back(r.rate_cpm);
                run.depths.push_back(r.depth_cm);
            }
        }
    }
    run.finalCcf = tracker.getReading().ccf_percentage;
    run.finalElapsed = tracker.getReading().elapsed_seconds;
    run.summary = tracker.finalizeSession(t0 + (uint32_t)llround(n * 1000.0 / fs));
    return run;
}

// Plays the segments in order.
static Run play(Shape shape, const std::vector<Segment>& segments,
                CPReadyConfig::KinematicProfile profile, unsigned seed, const Options& opt = Options()) {
    double total = 0.0;
    int expected = 0;
    for (const Segment& s : segments) {
        total += s.seconds;
        if (s.cpm > 0) expected += (int)floor(s.seconds / (60.0 / s.cpm));
    }
    auto x = [&](double t) {
        if (t < 0) return 0.0;
        double start = 0.0;
        for (const Segment& s : segments) {
            if (t < start + s.seconds) {
                const double local = t - start;
                if (s.cpm > 0) {
                    // Only whole strokes: cutting one off mid-push would teleport the chest
                    // back to the top, an unphysical acceleration spike. The leftover part
                    // of the segment is spent at rest.
                    const double T = 60.0 / s.cpm;
                    if (local >= floor(s.seconds / T) * T) return 0.0;
                    return displacement(shape, fmod(local / T, 1.0), T, s.depthCm);
                }
                if (s.bumpCm > 0.0) {
                    const double bumpLen = 0.12, bumpAt = 0.5 * (s.seconds - bumpLen);
                    if (local >= bumpAt && local < bumpAt + bumpLen) {
                        return 0.5 * s.bumpCm * (1.0 - cos(2.0 * PI_D * (local - bumpAt) / bumpLen));
                    }
                }
                return 0.0;
            }
            start += s.seconds;
        }
        return 0.0;
    };
    Run run = feed(x, total, profile, seed, opt);
    run.expected = expected;
    return run;
}

static float median(std::vector<float> v) {
    if (v.empty()) return 0.0f;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

static float percentile(std::vector<float> v, double p) {
    if (v.empty()) return 0.0f;
    std::sort(v.begin(), v.end());
    size_t i = (size_t)floor(p * (v.size() - 1) + 0.5);
    return v[i];
}

int main() {
    using P = CPReadyConfig::KinematicProfile;

    printf("== Detection, rate and depth across stroke shapes, cadences and depths ==\n");
    for (P profile : {P::MANIKIN_STANDARD, P::BENCH_TEST}) {
        for (Shape shape : {SINE, DUTY40, DWELL30, DWELL_BOUNCE}) {
            for (double cpm : {80.0, 100.0, 120.0, 150.0}) {
                for (double depth : {4.0, 5.5}) {
                    Run r = play(shape, {{30.0, cpm, depth}}, profile, 1);
                    const char* prof = profile == P::BENCH_TEST ? "bench" : "manikin";
                    char what[128];
                    snprintf(what, sizeof(what), "%s %s %.0f cpm %.1f cm: strokes detected",
                             prof, shapeName(shape), cpm, depth);
                    check(r.detected >= r.expected - 1 && r.detected <= r.expected + 1,
                          what, r.detected, r.expected - 1, r.expected + 1);
                    snprintf(what, sizeof(what), "%s %s %.0f cpm %.1f cm: median rate",
                             prof, shapeName(shape), cpm, depth);
                    checkNear(what, median(r.rates), cpm, 2.0);
                    snprintf(what, sizeof(what), "%s %s %.0f cpm %.1f cm: median depth",
                             prof, shapeName(shape), cpm, depth);
                    checkNear(what, median(r.depths), depth, 0.25);
                }
            }
        }
    }

    printf("\n== Depth across the range (35/35/30 dwell, 110 cpm) ==\n");
    for (double depth : {3.0, 4.0, 5.0, 6.0, 7.0}) {
        Run r = play(DWELL30, {{30.0, 110, depth}}, P::MANIKIN_STANDARD, 7);
        char what[128];
        snprintf(what, sizeof(what), "%.1f cm strokes: median depth", depth);
        checkNear(what, median(r.depths), depth, 0.25);
    }

    printf("\n== Per-stroke depth with stroke-to-stroke variation ==\n");
    {
        // 80 strokes; each has its own depth (4.0-7.0 cm) and period (+/-10 % around 110 cpm).
        Gauss g(11);
        struct Stroke { double start, period, depth; };
        std::vector<Stroke> strokes;
        double t = 0.5;
        for (int i = 0; i < 80; i++) {
            double period = (60.0 / 110.0) * (1.0 + 0.10 * (2.0 * g.uni() - 1.0));
            double depth = 4.0 + 3.0 * g.uni();
            strokes.push_back({t, period, depth});
            t += period;
        }
        const double total = t + 0.5;
        for (Shape shape : {DWELL30, DUTY40}) {
            auto x = [&](double tt) {
                for (const Stroke& s : strokes) {
                    if (tt >= s.start && tt < s.start + s.period) {
                        return displacement(shape, (tt - s.start) / s.period, s.period, s.depth);
                    }
                }
                return 0.0;
            };
            Run r = feed(x, total, P::MANIKIN_STANDARD, 12, Options());
            char what[128];
            snprintf(what, sizeof(what), "%s, varied strokes: all 80 detected", shapeName(shape));
            check(r.detected == 80, what, r.detected, 80, 80);
            std::vector<float> errors;
            for (size_t i = 1; i < r.allDepths.size() && i < strokes.size(); i++) {
                errors.push_back((float)fabs(r.allDepths[i] - strokes[i].depth));
            }
            snprintf(what, sizeof(what), "%s, varied strokes: median per-stroke error (cm)", shapeName(shape));
            check(median(errors) <= 0.30f, what, median(errors), 0.0, 0.30);
            snprintf(what, sizeof(what), "%s, varied strokes: 90th percentile error (cm)", shapeName(shape));
            check(percentile(errors, 0.90) <= 0.60f, what, percentile(errors, 0.90), 0.0, 0.60);
        }
    }

    printf("\n== First stroke and the stroke after a pause (depth from rest) ==\n");
    {
        // Hands rest for 1 s after START, as they do on the vest, before the first push.
        Run r = play(DWELL30, {{1.0, 0, 0}, {10.0, 110, 5.5}, {5.0, 0, 0}, {10.0, 110, 5.5}},
                     P::MANIKIN_STANDARD, 13);
        check(r.firstDepths.size() == 2, "two strokes start from rest", r.firstDepths.size(), 2, 2);
        for (size_t i = 0; i < r.firstDepths.size(); i++) {
            checkNear(i == 0 ? "session's first stroke: depth" : "first stroke after the pause: depth",
                      r.firstDepths[i], 5.5, 0.50);
        }
    }

    printf("\n== Robustness: sensor offset, heavier noise ==\n");
    {
        Options offset;
        offset.offsetG = 0.03;   // 30 mg left after calibration
        Run r = play(DWELL30, {{30.0, 110, 5.5}}, P::MANIKIN_STANDARD, 14, offset);
        check(r.detected >= r.expected - 1 && r.detected <= r.expected + 1,
              "30 mg offset: strokes detected", r.detected, r.expected - 1, r.expected + 1);
        checkNear("30 mg offset: median depth", median(r.depths), 5.5, 0.25);

        Options noisy;
        noisy.noiseG = 0.02;     // 20 mg noise, several times a real MPU-6050's
        Run n = play(DWELL30, {{30.0, 110, 5.5}}, P::MANIKIN_STANDARD, 15, noisy);
        check(n.detected >= n.expected - 1 && n.detected <= n.expected + 1,
              "20 mg noise: strokes detected", n.detected, n.expected - 1, n.expected + 1);
        checkNear("20 mg noise: median depth", median(n.depths), 5.5, 0.30);
    }

    printf("\n== K still scales depth (Manikin Calibration and SET_K) ==\n");
    {
        Options k2;
        k2.k = 2.0f * CPReadyConfig::DEPTH_CALIBRATION_K;
        Run r = play(DWELL30, {{20.0, 110, 2.5}}, P::MANIKIN_STANDARD, 16, k2);
        checkNear("K = 2 x default doubles 2.5 cm to 5.0 cm", median(r.depths), 5.0, 0.25);
    }

    printf("\n== Known limit (informational, not asserted): strong 4 mm / 8 Hz spring ringing ==\n");
    for (double cpm : {80.0, 110.0, 140.0}) {
        Run r = play(DWELL_STRONG_BOUNCE, {{30.0, cpm, 5.5}}, P::MANIKIN_STANDARD, 1);
        printf("[INFO] %.0f cpm: %d of %d strokes detected, median rate %.1f, median depth %.2f\n",
               cpm, r.detected, r.expected, median(r.rates), median(r.depths));
    }

    printf("\n== Shallow strokes are still counted ==\n");
    {
        Run r = play(DWELL30, {{30.0, 110, 3.0}}, P::MANIKIN_STANDARD, 2);
        check(r.detected >= r.expected - 1, "3.0 cm strokes at 110 cpm detected", r.detected, r.expected - 1, r.expected + 1);
    }

    printf("\n== No phantom strokes while hands are still ==\n");
    {
        Run r = play(DWELL30, {{20.0, 0, 0}}, P::MANIKIN_STANDARD, 3);
        check(r.detected == 0, "strokes during 20 s of sensor noise only", r.detected, 0, 0);
        Run b = play(DWELL30, {{20.0, 0, 0}}, P::BENCH_TEST, 3);
        check(b.detected == 0, "strokes during 20 s of noise (bench profile)", b.detected, 0, 0);
    }

    printf("\n== A knock during a pause is not a compression ==\n");
    {
        std::vector<Segment> base = {{10.0, 110, 5.5}, {6.0, 0, 0}, {10.0, 110, 5.5}};
        std::vector<Segment> knock = {{10.0, 110, 5.5}, {6.0, 0, 0, 0.3}, {10.0, 110, 5.5}};
        std::vector<Segment> realStroke = {{10.0, 110, 5.5}, {6.0, 0, 0, 3.0}, {10.0, 110, 5.5}};
        Run r0 = play(DWELL30, base, P::MANIKIN_STANDARD, 17);
        Run r1 = play(DWELL30, knock, P::MANIKIN_STANDARD, 17);
        Run r2 = play(DWELL30, realStroke, P::MANIKIN_STANDARD, 17);
        check(r1.detected == r0.detected, "3 mm knock in a pause: stroke count unchanged", r1.detected, r0.detected, r0.detected);
        // The same pulse at 3 cm is a real (if odd) compression and must still count,
        // which shows the knock reaches the detector and is rejected on its depth.
        check(r2.detected == r0.detected + 1, "same pulse at 3 cm: counted as one stroke", r2.detected, r0.detected + 1, r0.detected + 1);
    }

    printf("\n== Pause handling: rate, CCF and the post-pause stroke ==\n");
    {
        Run r = play(DWELL30, {{10.0, 110, 5.5}, {6.0, 0, 0}, {10.0, 110, 5.5}}, P::MANIKIN_STANDARD, 4);
        check(r.postPauseStrokes == 2, "first-stroke flags (session start + after pause)", r.postPauseStrokes, 2, 2);
        check(r.zeroRatePostPause == r.postPauseStrokes, "post-pause strokes report no rate", r.zeroRatePostPause, r.postPauseStrokes, r.postPauseStrokes);
        check(r.summary.final_ccf_percent >= 65.0f && r.summary.final_ccf_percent <= 80.0f,
              "session CCF with a 6 s pause in 26 s", r.summary.final_ccf_percent, 65.0, 80.0);
        checkNear("session mean rate ignores post-pause strokes", r.summary.avg_rate_cpm, 110.0, 2.0);
        checkNear("session mean depth", r.summary.avg_depth_cm, 5.5, 0.25);
    }

    printf("\n== Live CCF decays during a pause instead of freezing ==\n");
    {
        Run r = play(DWELL30, {{10.0, 110, 5.5}, {10.0, 0, 0}}, P::MANIKIN_STANDARD, 5);
        check(r.finalCcf <= 55.0f, "live CCF after 10 s on / 10 s off", r.finalCcf, 0.0, 55.0);
    }

    printf("\n== PAUSE / RESUME excludes paused time ==\n");
    {
        CompressionTracker tracker;
        tracker.startSession(1000);
        for (uint32_t ms = 1000; ms < 6000; ms += 10) tracker.processSample(0.0f, 0.0f, ms);
        tracker.pauseSession(6000);
        for (uint32_t ms = 6000; ms < 16000; ms += 10) tracker.processSample(0.0f, 0.0f, ms);   // ignored while paused
        tracker.resumeSession(16000);
        for (uint32_t ms = 16000; ms < 21000; ms += 10) tracker.processSample(0.0f, 0.0f, ms);
        check(tracker.getReading().elapsed_seconds == 9, "elapsed seconds after 5 s + 10 s paused + 5 s",
              tracker.getReading().elapsed_seconds, 9, 9);
        CPRSessionSummary s = tracker.finalizeSession(21000);
        check(s.total_duration_sec == 10, "summary duration excludes the pause", s.total_duration_sec, 10, 10);
        check(!tracker.isSessionActive(), "finalize ends the session", tracker.isSessionActive(), 0, 0);
        bool sampled = tracker.processSample(1.0f, 1.0f, 22000);
        check(!sampled, "samples after finalize are ignored", sampled, 0, 0);
    }

    printf("\n== Flags and cue handling ==\n");
    {
        Run r = play(DWELL30, {{10.0, 110, 5.5}}, P::MANIKIN_STANDARD, 6);
        bool estimated = (r.lastFlags & CADENCE_FLAG_RECOIL_ESTIMATED) != 0;
        check(estimated, "live packets mark recoil as estimated", estimated, 1, 1);
        bool summaryEstimated = (r.summary.quality_flags & CADENCE_FLAG_RECOIL_ESTIMATED) != 0;
        check(summaryEstimated, "summary marks recoil as estimated", summaryEstimated, 1, 1);
        check(r.summary.total_compressions == (uint16_t)r.detected, "summary count matches strokes",
              r.summary.total_compressions, r.detected, r.detected);
        CPRMetricsPacket pkt = r.summary.toPacket();
        check(pkt.stroke_count == r.summary.total_compressions, "16-bit stroke count in packet",
              pkt.stroke_count, r.summary.total_compressions, r.summary.total_compressions);
    }

    printf("\n== Tilted sensor: vertical acceleration from the gravity direction ==\n");
    {
        const double tilt = 30.0 * PI_D / 180.0;
        // At rest the sensor reads 1 g along "up", which is tilted 30 deg from its z axis.
        const Vec3 up = {0.0f, (float)sin(tilt), (float)cos(tilt)};
        GravityAxis axis;
        axis.reset();
        axis.setFromRest(up);
        checkNear("learned tilt (deg)", axis.tiltDegrees(), 30.0, 0.1);
        // Accelerating downward at 0.5 g reduces the reading along "up" to 0.5 g.
        const Vec3 pushed = {0.0f, 0.5f * up.y, 0.5f * up.z};
        checkNear("projected dynamic acceleration (g)", axis.dynamicG(pushed), -0.5, 0.001);
        // The z-only method this replaces reads cos(30 deg) of it.
        checkNear("z-only reading, for comparison (g)", pushed.z - up.z, -0.5 * cos(tilt), 0.001);
    }

    printf("\n%s: %d failure(s)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
    return failures;
}
