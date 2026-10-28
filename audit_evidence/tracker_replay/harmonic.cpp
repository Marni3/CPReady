// Prototype of the windowed Fourier-series (harmonic) depth estimator from
// Ruiz de Gauna et al., Biomed Res Int 2016 (PMC5143701), run on the same
// synthetic strokes as replay.cpp. ESP32-sized: 100 Hz, 3 s window, N = 6.
#include <cstdio>
#include <cmath>
#include <initializer_list>

static const double PI_D = 3.14159265358979323846, G_CM = 980.665;
enum Shape { SINE, DUTY40, DWELL30 };

static double disp(Shape s, double u, double D, double lean) {
    if (s == SINE) return lean + 0.5 * D * (1 - cos(2 * PI_D * u));
    if (s == DUTY40) { const double c = 0.4;
        return u < c ? lean + 0.5 * D * (1 - cos(PI_D * u / c)) : lean + 0.5 * D * (1 + cos(PI_D * (u - c) / (1 - c))); }
    const double c = 0.35, r = 0.35;
    if (u < c) return lean + 0.5 * D * (1 - cos(PI_D * u / c));
    if (u < c + r) return lean + 0.5 * D * (1 + cos(PI_D * (u - c) / r));
    return lean;
}

struct Gauss { unsigned long long s; explicit Gauss(unsigned seed) : s(seed * 2654435761ull + 1) {}
    double uni() { s = s * 6364136223846793005ull + 1442695040888963407ull; return ((s >> 11) + 0.5) / 9007199254740992.0; }
    double operator()() { double a = uni(), b = uni(); return sqrt(-2 * log(a)) * cos(2 * PI_D * b); } };

// Estimate depth (cm) and rate (cpm) from one window of net acceleration (g).
static void estimate(const double* a, int n, double fs, double& depth, double& cpm) {
    // 1. Fundamental period by autocorrelation over 0.35..1.0 s lags.
    double mean = 0; for (int i = 0; i < n; i++) mean += a[i]; mean /= n;
    int bestLag = 0; double best = -1e9;
    for (int lag = (int)(0.35 * fs); lag <= (int)(1.0 * fs); lag++) {
        double acc = 0; for (int i = 0; i + lag < n; i++) acc += (a[i] - mean) * (a[i + lag] - mean);
        acc /= (n - lag);
        if (acc > best) { best = acc; bestLag = lag; }
    }
    // Parabolic refinement of the peak lag.
    auto ac = [&](int lag) { double s = 0; for (int i = 0; i + lag < n; i++) s += (a[i] - mean) * (a[i + lag] - mean); return s / (n - lag); };
    double ym = ac(bestLag - 1), y0 = ac(bestLag), yp = ac(bestLag + 1);
    double frac = 0.5 * (ym - yp) / (ym - 2 * y0 + yp);
    double T = (bestLag + frac) / fs;
    cpm = 60.0 / T;
    // 2. Fourier coefficients over an integer number of periods.
    int periods = (int)floor((n / fs) / T);
    int m = (int)llround(periods * T * fs);
    const int N = 6;
    double re[N + 1], im[N + 1];
    double w0 = 2 * PI_D / T;
    for (int k = 1; k <= N; k++) {
        re[k] = im[k] = 0;
        for (int i = 0; i < m; i++) { double ph = k * w0 * i / fs; re[k] += a[i] * cos(ph); im[k] += a[i] * sin(ph); }
        re[k] *= 2.0 / m; im[k] *= 2.0 / m;
    }
    // 3. Displacement = -sum a_k/(k w0)^2, peak-to-peak over one period.
    double lo = 1e9, hi = -1e9;
    for (int i = 0; i < 200; i++) {
        double t = T * i / 200.0, x = 0;
        for (int k = 1; k <= N; k++) {
            double s = 1.0 / ((k * w0) * (k * w0));
            x -= s * (re[k] * cos(k * w0 * t) + im[k] * sin(k * w0 * t));
        }
        lo = fmin(lo, x); hi = fmax(hi, x);
    }
    depth = (hi - lo) * G_CM;  // a in g -> cm
}

int main() {
    const char* names[] = {"sine", "40/60 duty", "35/35/30 dwell"};
    const double fs = 100.0, win = 3.0;
    const int n = (int)(win * fs);
    double a[400];
    printf("%-14s %5s %6s %5s | %8s %8s\n", "shape", "cpm", "trueD", "lean", "estD", "estCpm");
    for (int s = 0; s < 3; s++)
        for (double cpm : {80.0, 100.0, 120.0, 150.0})
            for (double D : {4.0, 5.5, 7.0}) {
                double lean = (D == 5.5) ? 1.5 : 0.0;   // leaning is invisible to this method too
                Gauss g(7);
                const double T = 60.0 / cpm, h = 1e-4, phase0 = 0.37;  // arbitrary window phase
                for (int i = 0; i < n; i++) {
                    double t = i / fs;
                    auto x = [&](double tt) { return disp((Shape)s, fmod(tt / T + phase0, 1.0), D, lean); };
                    a[i] = (x(t + h) - 2 * x(t) + x(t - h)) / (h * h) / G_CM + 0.005 * g();
                }
                double estD, estCpm;
                estimate(a, n, fs, estD, estCpm);
                printf("%-14s %5.0f %6.1f %5.1f | %8.2f %8.1f\n", names[s], cpm, D, lean, estD, estCpm);
            }
    return 0;
}
