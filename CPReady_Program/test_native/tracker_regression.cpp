// Native regression test for CompressionTracker (no ESP32 needed).
//
// Builds the production header against shim/Arduino.h and drives it with chest
// displacement waveforms whose depth, rate and pauses are known. Each check
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

static const double G_CM = 980.665;
static const double PI_D = 3.14159265358979323846;
static int failures = 0;

static void check(bool ok, const char* what, double got, double lo, double hi) {
    printf("[%s] %-62s got %8.2f  (expected %.2f .. %.2f)\n", ok ? "PASS" : "FAIL", what, got, lo, hi);
    if (!ok) failures++;
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

struct Segment {
    double seconds;   // duration
    double cpm;       // 0 = hands still
    double depthCm;
};

struct Run {
    int detected = 0;
    int expected = 0;
    std::vector<float> rates;          // rates of strokes carrying a cadence
    int zeroRatePostPause = 0;         // post-pause strokes reporting rate 0
    int postPauseStrokes = 0;
    uint8_t lastFlags = 0;
    float finalCcf = 0.0f;
    uint32_t finalElapsed = 0;
    CPRSessionSummary summary;
};

// Plays the segments in order through the tracker at 100 Hz with the production EMA.
static Run play(Shape shape, const std::vector<Segment>& segments,
                CPReadyConfig::KinematicProfile profile, unsigned seed) {
    CompressionTracker tracker;
    tracker.setProfile(profile);
    const uint32_t t0 = 5000;
    tracker.startSession(t0);

    Gauss noise(seed);
    const double fs = 100.0, h = 1e-4;
    float ema = 0.0f;
    Run run;
    double tSession = 0.0;

    for (const Segment& seg : segments) {
        const double T = seg.cpm > 0 ? 60.0 / seg.cpm : 1.0;
        if (seg.cpm > 0) run.expected += (int)floor(seg.seconds / T);
        for (double t = 0.0; t < seg.seconds; t += 1.0 / fs) {
            double a = 0.0;
            if (seg.cpm > 0) {
                auto x = [&](double tt) {
                    if (tt < 0) return 0.0;
                    return displacement(shape, fmod(tt / T, 1.0), T, seg.depthCm);
                };
                a = (x(t + h) - 2.0 * x(t) + x(t - h)) / (h * h);
            }
            float net = (float)(a / G_CM + 0.005 * noise());
            ema = 0.25f * net + 0.75f * ema;
            uint32_t ms = t0 + (uint32_t)llround(tSession * 1000.0);
            if (tracker.processSample(ema, ms)) {
                const CPRReading& r = tracker.getReading();
                run.detected++;
                run.lastFlags = r.quality_flags;
                if (r.quality_flags & CADENCE_FLAG_FIRST_STROKE) {
                    run.postPauseStrokes++;
                    if (r.rate_cpm == 0.0f) run.zeroRatePostPause++;
                } else if (r.rate_cpm > 0.0f) {
                    run.rates.push_back(r.rate_cpm);
                }
            }
            tSession += 1.0 / fs;
        }
    }
    run.finalCcf = tracker.getReading().ccf_percentage;
    run.finalElapsed = tracker.getReading().elapsed_seconds;
    run.summary = tracker.finalizeSession(t0 + (uint32_t)llround(tSession * 1000.0));
    return run;
}

static float median(std::vector<float> v) {
    if (v.empty()) return 0.0f;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

int main() {
    using P = CPReadyConfig::KinematicProfile;

    printf("== Detection and rate across stroke shapes, cadences and depths ==\n");
    for (P profile : {P::MANIKIN_STANDARD, P::BENCH_TEST}) {
        for (Shape shape : {SINE, DUTY40, DWELL30, DWELL_BOUNCE}) {
            for (double cpm : {80.0, 100.0, 120.0, 150.0}) {
                for (double depth : {4.0, 5.5}) {
                    Run r = play(shape, {{30.0, cpm, depth}}, profile, 1);
                    char what[128];
                    snprintf(what, sizeof(what), "%s %s %.0f cpm %.1f cm: strokes detected",
                             profile == P::BENCH_TEST ? "bench" : "manikin", shapeName(shape), cpm, depth);
                    check(r.detected >= r.expected - 1 && r.detected <= r.expected + 1,
                          what, r.detected, r.expected - 1, r.expected + 1);
                    snprintf(what, sizeof(what), "%s %s %.0f cpm %.1f cm: median rate",
                             profile == P::BENCH_TEST ? "bench" : "manikin", shapeName(shape), cpm, depth);
                    float rate = median(r.rates);
                    check(fabs(rate - cpm) <= 2.0, what, rate, cpm - 2.0, cpm + 2.0);
                }
            }
        }
    }

    printf("\n== Known limit (informational, not asserted): strong 4 mm / 8 Hz spring ringing ==\n");
    for (double cpm : {80.0, 110.0, 140.0}) {
        Run r = play(DWELL_STRONG_BOUNCE, {{30.0, cpm, 5.5}}, P::MANIKIN_STANDARD, 1);
        printf("[INFO] %.0f cpm: %d of %d strokes detected, median rate %.1f\n",
               cpm, r.detected, r.expected, median(r.rates));
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

    printf("\n== Pause handling: rate, CCF and the post-pause stroke ==\n");
    {
        Run r = play(DWELL30, {{10.0, 110, 5.5}, {6.0, 0, 0}, {10.0, 110, 5.5}}, P::MANIKIN_STANDARD, 4);
        check(r.postPauseStrokes == 2, "first-stroke flags (session start + after pause)", r.postPauseStrokes, 2, 2);
        check(r.zeroRatePostPause == r.postPauseStrokes, "post-pause strokes report no rate", r.zeroRatePostPause, r.postPauseStrokes, r.postPauseStrokes);
        check(r.summary.final_ccf_percent >= 65.0f && r.summary.final_ccf_percent <= 80.0f,
              "session CCF with a 6 s pause in 26 s", r.summary.final_ccf_percent, 65.0, 80.0);
        check(fabs(r.summary.avg_rate_cpm - 110.0f) <= 2.0f, "session mean rate ignores post-pause strokes",
              r.summary.avg_rate_cpm, 108.0, 112.0);
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
        for (uint32_t ms = 1000; ms < 6000; ms += 10) tracker.processSample(0.0f, ms);
        tracker.pauseSession(6000);
        for (uint32_t ms = 6000; ms < 16000; ms += 10) tracker.processSample(0.0f, ms);   // ignored while paused
        tracker.resumeSession(16000);
        for (uint32_t ms = 16000; ms < 21000; ms += 10) tracker.processSample(0.0f, ms);
        check(tracker.getReading().elapsed_seconds == 9, "elapsed seconds after 5 s + 10 s paused + 5 s",
              tracker.getReading().elapsed_seconds, 9, 9);
        CPRSessionSummary s = tracker.finalizeSession(21000);
        check(s.total_duration_sec == 10, "summary duration excludes the pause", s.total_duration_sec, 10, 10);
        check(!tracker.isSessionActive(), "finalize ends the session", tracker.isSessionActive(), 0, 0);
        bool sampled = tracker.processSample(1.0f, 22000);
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

    printf("\n%s: %d failure(s)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
    return failures;
}
