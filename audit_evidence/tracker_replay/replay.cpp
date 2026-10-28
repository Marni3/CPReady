// Offline replay of the production CompressionTracker against physically
// consistent chest displacement waveforms.
//
// x(t) = downward chest displacement (cm). netAccel = x''/g, which is what
// SensorManager produces for a face-up sensor: -(z_reading - z_offset).
// The 100 Hz samples go through the same EMA (alpha 0.25) as SensorManager.

#include <cstdio>
#include <cmath>
#include <vector>
#include <algorithm>
#include "CompressionTracker.h"

// Small deterministic Gaussian source (the local toolchain lacks <random>).
struct Gauss {
    uint64_t s;
    explicit Gauss(unsigned seed) : s(seed * 2654435761ull + 1) {}
    double uni() { s = s * 6364136223846793005ull + 1442695040888963407ull; return ((s >> 11) + 0.5) / 9007199254740992.0; }
    double operator()() { double u1 = uni(), u2 = uni(); return sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2); }
};

static const double G_CM = 980.665;      // cm/s^2
static const double PI_D = 3.14159265358979323846;

enum class Shape { SINE, DUTY40, DWELL30 };

// Displacement within one cycle, phase u in [0,1). D = stroke depth (cm),
// lean = residual displacement at the top (cm).
static double displacement(Shape shape, double u, double D, double lean) {
    switch (shape) {
        case Shape::SINE:
            return lean + 0.5 * D * (1.0 - cos(2.0 * PI_D * u));
        case Shape::DUTY40: {  // 40 % push, 60 % release, no dwell
            const double c = 0.40;
            if (u < c) return lean + 0.5 * D * (1.0 - cos(PI_D * u / c));
            return lean + 0.5 * D * (1.0 + cos(PI_D * (u - c) / (1.0 - c)));
        }
        case Shape::DWELL30: { // 35 % push, 35 % release, 30 % dwell at top
            const double c = 0.35, r = 0.35;
            if (u < c) return lean + 0.5 * D * (1.0 - cos(PI_D * u / c));
            if (u < c + r) return lean + 0.5 * D * (1.0 + cos(PI_D * (u - c) / r));
            return lean;
        }
    }
    return 0.0;
}

struct Result {
    int truth = 0, detected = 0, recoilOk = 0;
    std::vector<float> rates, depths;
};

static float median(std::vector<float> v) {
    if (v.empty()) return NAN;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

static Result run(Shape shape, double cpm, double D, double lean, double seconds,
                  CPReadyConfig::KinematicProfile profile, unsigned seed) {
    const double T = 60.0 / cpm;
    const double fs = 100.0, dt = 1.0 / fs, h = 1e-4;
    Gauss noise(seed);  // scaled to ~5 mg differential sensor noise below

    CompressionTracker tr;
    tr.setProfile(profile);
    const uint32_t t0 = 5000;  // pretend the device booted 5 s ago
    tr.startSession(t0);

    // Hands start 0.6 s after START, as after the app countdown.
    const double startDelay = 0.6;
    float ema = 0.0f;
    Result r;
    for (double t = 0.0; t < seconds; t += dt) {
        double a = 0.0;
        if (t > startDelay) {
            auto x = [&](double tt) {
                double ph = fmod((tt - startDelay) / T, 1.0);
                if (tt < startDelay) return lean;
                return displacement(shape, ph, D, lean);
            };
            a = (x(t + h) - 2.0 * x(t) + x(t - h)) / (h * h);  // cm/s^2, + = down
        }
        float net = (float)(a / G_CM + 0.005 * noise());
        ema = 0.25f * net + 0.75f * ema;
        uint32_t ms = t0 + (uint32_t)llround(t * 1000.0);
        // Revision 3 of the tracker also takes the unfiltered sample (for depth).
        if (tr.processSample(ema, net, ms)) {
            const CPRReading& rd = tr.getReading();
            r.detected++;
            if (rd.recoil_complete) r.recoilOk++;
            if (!(rd.quality_flags & CADENCE_FLAG_FIRST_STROKE)) {
                r.rates.push_back(rd.rate_cpm);
                r.depths.push_back(rd.depth_cm);
            }
        }
    }
    r.truth = (int)floor((seconds - startDelay) / T);
    return r;
}

static const char* shapeName(Shape s) {
    return s == Shape::SINE ? "sine" : s == Shape::DUTY40 ? "40/60 duty" : "35/35/30 dwell";
}

int main() {
    using P = CPReadyConfig::KinematicProfile;
    printf("=== A. Detection, rate and depth vs cadence (true depth 5.5 cm, no lean, manikin profile, 30 s) ===\n");
    printf("%-14s %5s | %5s %5s %6s | %8s %8s | %6s\n",
           "shape", "cpm", "true", "det", "det%", "rate_med", "dep_med", "recoil");
    const Shape shapes[] = {Shape::SINE, Shape::DUTY40, Shape::DWELL30};
    const double rates[] = {80, 90, 100, 110, 120, 130, 140, 150};
    for (Shape s : shapes) {
        for (double cpm : rates) {
            Result r = run(s, cpm, 5.5, 0.0, 30.0, P::MANIKIN_STANDARD, 1);
            printf("%-14s %5.0f | %5d %5d %5.0f%% | %8.1f %8.2f | %5.0f%%\n",
                   shapeName(s), cpm, r.truth, r.detected,
                   100.0 * r.detected / std::max(1, r.truth),
                   median(r.rates), median(r.depths),
                   r.detected ? 100.0 * r.recoilOk / r.detected : 0.0);
        }
    }

    printf("\n=== B. 'Recoil' flag vs real leaning (35/35/30 dwell, 120 cpm, manikin profile, 30 s) ===\n");
    printf("%-34s | %5s %5s | %8s | %6s\n", "case", "true", "det", "dep_med", "recoil");
    struct Case { const char* name; double D, lean; } cases[] = {
        {"3.5 cm stroke, full release",      3.5, 0.0},
        {"4.0 cm stroke, full release",      4.0, 0.0},
        {"5.5 cm stroke, full release",      5.5, 0.0},
        {"5.5 cm stroke, 1.5 cm LEANING",    5.5, 1.5},
        {"6.0 cm stroke, 2.0 cm LEANING",    6.0, 2.0},
    };
    for (auto& c : cases) {
        Result r = run(Shape::DWELL30, 120, c.D, c.lean, 30.0, P::MANIKIN_STANDARD, 2);
        printf("%-34s | %5d %5d | %8.2f | %5.0f%%\n", c.name, r.truth, r.detected, median(r.depths),
               r.detected ? 100.0 * r.recoilOk / r.detected : 0.0);
    }

    printf("\n=== C. Depth vs true depth (35/35/30 dwell, 120 cpm, manikin profile) ===\n");
    printf("%6s | %5s %5s | %8s\n", "true", "true#", "det", "dep_med");
    for (double D : {3.0, 4.0, 5.0, 5.5, 6.0, 7.0}) {
        Result r = run(Shape::DWELL30, 120, D, 0.0, 30.0, P::MANIKIN_STANDARD, 3);
        printf("%6.1f | %5d %5d | %8.2f\n", D, r.truth, r.detected, median(r.depths));
    }

    printf("\n=== D. Same true depth (5.5 cm), different stroke shape, bench profile (0.25 g start) ===\n");
    printf("%-14s %5s | %5s %5s | %8s %8s | %s\n", "shape", "cpm", "true", "det", "rate_med", "dep_med", "recoil");
    for (Shape s : shapes) {
        for (double cpm : {100.0, 110.0, 120.0, 140.0}) {
            Result r = run(s, cpm, 5.5, 0.0, 30.0, P::BENCH_TEST, 4);
            printf("%-14s %5.0f | %5d %5d | %8.1f %8.2f | recoil %3.0f%%\n", shapeName(s), cpm, r.truth, r.detected,
                   median(r.rates), median(r.depths), r.detected ? 100.0 * r.recoilOk / r.detected : 0.0);
        }
    }
    return 0;
}

