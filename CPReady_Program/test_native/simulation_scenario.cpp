// Native check of the simulation firmware's scenario (no ESP32 needed).
//
// Plays SyntheticVest's cue drill through the production CompressionTracker the way
// src/simulation.cpp does (100 Hz, the SensorManager low-pass on the detection input,
// the raw signal for depth, each cue cleared after it is sent). Checks that every phase
// is measured at its own depth and rate, and that each coaching cue fires in order.
//
// Build (from this folder):
//   g++ -std=c++17 -O2 -I shim -I ../include simulation_scenario.cpp -o simulation_scenario
//   ./simulation_scenario

#include <cstdio>
#include <cmath>
#include <vector>
#include <algorithm>
#include "CompressionTracker.h"
#include "SyntheticVest.h"

static int failures = 0;

static void check(bool ok, const char* what, double got, double lo, double hi) {
    printf("[%s] %-56s got %8.2f  (expected %.2f .. %.2f)\n", ok ? "PASS" : "FAIL", what, got, lo, hi);
    if (!ok) failures++;
}

static float median(std::vector<float> v) {
    if (v.empty()) return 0.0f;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

static const char* cueName(uint8_t c) {
    switch (c) {
        case PROMPT_PUSH_HARDER: return "push harder";
        case PROMPT_PUSH_LESS: return "push less";
        case PROMPT_RELEASE_FULLY: return "release fully";
        case PROMPT_SPEED_UP: return "speed up";
        case PROMPT_SLOW_DOWN: return "slow down";
        case PROMPT_GOOD_JOB: return "good job";
        default: return "?";
    }
}

int main() {
    CompressionTracker tracker;
    SyntheticVest vest;
    const uint32_t t0 = 10000;
    tracker.startSession(t0);
    vest.begin(t0, false);

    std::vector<std::vector<float>> depths(SimConfig::PHASE_COUNT), rates(SimConfig::PHASE_COUNT);
    std::vector<uint8_t> cues;
    std::vector<uint8_t> cuePhases;
    float filtered = 0.0f;

    for (uint32_t ms = t0; ms < t0 + 75000; ms += 10) {
        const uint8_t phase = vest.phaseIndexAt(ms);
        const float raw = vest.netAccelAt(ms);
        filtered = CPReadyConfig::LOWPASS_FILTER_ALPHA * raw +
                   (1.0f - CPReadyConfig::LOWPASS_FILTER_ALPHA) * filtered;
        if (tracker.processSample(filtered, raw, ms)) {
            const CPRReading& r = tracker.getReading();
            if (!(r.quality_flags & CADENCE_FLAG_FIRST_STROKE)) {
                depths[phase].push_back(r.depth_cm);
                rates[phase].push_back(r.rate_cpm);
            }
            if (r.audio_prompt_code != PROMPT_NONE) {
                printf("[CUE] %-14s at %5.1f s (phase: %s)\n", cueName(r.audio_prompt_code),
                       (ms - t0) / 1000.0, SimConfig::PHASES[phase].label);
                cues.push_back(r.audio_prompt_code);
                cuePhases.push_back(phase);
            }
            tracker.clearAudioPrompt();
        }
    }

    printf("\n== Each phase is measured at its own depth and rate ==\n");
    for (uint8_t i = 0; i < SimConfig::PHASE_COUNT; i++) {
        const SimConfig::Phase& p = SimConfig::PHASES[i];
        char what[96];
        snprintf(what, sizeof(what), "%s: median depth", p.label);
        float d = median(depths[i]);
        check(fabsf(d - p.depthCm) <= 0.3f, what, d, p.depthCm - 0.3, p.depthCm + 0.3);
        snprintf(what, sizeof(what), "%s: median rate", p.label);
        float r = median(rates[i]);
        check(fabsf(r - p.rateCpm) <= 2.0f, what, r, p.rateCpm - 2.0, p.rateCpm + 2.0);
    }

    printf("\n== Every coaching cue fires, in scenario order ==\n");
    const uint8_t expected[] = {PROMPT_PUSH_HARDER, PROMPT_PUSH_LESS, PROMPT_SPEED_UP,
                                PROMPT_SLOW_DOWN, PROMPT_GOOD_JOB};
    size_t next = 0;
    for (uint8_t c : cues) {
        if (next < sizeof(expected) && c == expected[next]) next++;
    }
    check(next == sizeof(expected), "expected cues found in order", (double)next,
          (double)sizeof(expected), (double)sizeof(expected));
    bool noRelease = std::find(cues.begin(), cues.end(), PROMPT_RELEASE_FULLY) == cues.end();
    check(noRelease, "no 'release fully' cue (recoil is estimated)", noRelease, 1, 1);

    printf("\n%s: %d failure(s)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
    return failures;
}
