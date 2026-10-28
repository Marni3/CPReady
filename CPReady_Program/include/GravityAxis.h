#ifndef GRAVITY_AXIS_H
#define GRAVITY_AXIS_H

#include <math.h>

struct Vec3 {
    float x;
    float y;
    float z;
};

/**
 * The vertical direction of one accelerometer, learned from its resting reading.
 *
 * Using only the sensor's z axis reads a tilted pad short by cos(tilt): 13 % at 30
 * degrees. That error then hides inside K. At rest the sensor measures gravity alone,
 * so the mean resting vector points straight up in the sensor's own axes. Projecting
 * every sample onto it measures the vertical motion whatever the mounting angle.
 * Before calibration the axis is the sensor z axis with no offset, matching the
 * uncalibrated behaviour of the z-only code.
 */
class GravityAxis {
public:
    void reset() {
        ux = 0.0f; uy = 0.0f; uz = 1.0f;
        magnitudeG = 0.0f;
    }

    // Learns the axis from the mean resting reading (g). Returns false and keeps the
    // previous axis if the reading is too small to have a direction.
    bool setFromRest(const Vec3& mean) {
        float m = sqrtf(mean.x * mean.x + mean.y * mean.y + mean.z * mean.z);
        if (m < 0.1f) return false;
        ux = mean.x / m;
        uy = mean.y / m;
        uz = mean.z / m;
        magnitudeG = m;
        return true;
    }

    // Dynamic acceleration along the learned vertical (g); 0 at rest. Downward
    // acceleration of the sensor gives a negative value, as the z-only code did.
    float dynamicG(const Vec3& a) const {
        return a.x * ux + a.y * uy + a.z * uz - magnitudeG;
    }

    // Angle between the sensor z axis and the vertical, in degrees.
    float tiltDegrees() const {
        float c = uz;
        if (c > 1.0f) c = 1.0f;
        if (c < -1.0f) c = -1.0f;
        return acosf(c) * 57.29578f;
    }

    float magnitude() const { return magnitudeG; }

private:
    float ux = 0.0f;
    float uy = 0.0f;
    float uz = 1.0f;
    float magnitudeG = 0.0f;
};

#endif // GRAVITY_AXIS_H
