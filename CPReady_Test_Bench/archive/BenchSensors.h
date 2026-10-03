#ifndef BENCH_SENSORS_H
#define BENCH_SENSORS_H

#include <Wire.h>
#include <MPU6050.h>
#include "BenchConfig.h"

/**
 * Sensor Subsystem for CPReady Test Bench
 * Supports dynamic runtime switching between Single MPU (0x68) and Dual MPU (0x68 & 0x69).
 */
class BenchSensors {
private:
    MPU6050 chestSensor;
    MPU6050 baseSensor;

    bool isChestOnline;
    bool isBaseOnline;
    bool dualModeRequested;

    float chestGravityOffset;
    float baseGravityOffset;
    float lastFilteredNetAccel;
    uint32_t lastSampleMicros;

    // Calibration accumulators
    float calChestSum;
    float calBaseSum;
    uint16_t calSampleCount;
    bool isCalibrated;

public:
    BenchSensors() 
        : chestSensor(BENCH_CHEST_I2C_ADDR), 
          baseSensor(BENCH_BASE_I2C_ADDR),
          isChestOnline(false), isBaseOnline(false), dualModeRequested(false),
          chestGravityOffset(0.0f), baseGravityOffset(0.0f),
          lastFilteredNetAccel(0.0f), lastSampleMicros(0),
          calChestSum(0.0f), calBaseSum(0.0f), calSampleCount(0), isCalibrated(false) {}

    bool begin(bool requestDual = false) {
        dualModeRequested = requestDual;

        Wire.begin(BENCH_I2C_SDA_PIN, BENCH_I2C_SCL_PIN);
        Wire.setClock(BENCH_I2C_CLOCK_HZ);
        Wire.setTimeOut(BENCH_I2C_TIMEOUT_MS);

        chestSensor.initialize();
        isChestOnline = chestSensor.testConnection();

        baseSensor.initialize();
        isBaseOnline = baseSensor.testConnection();

        if (isChestOnline) {
            chestSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4); // +/- 4g = 8192 LSB/g
        }

        if (isBaseOnline) {
            baseSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }

        return isChestOnline; // Primary chest sensor is mandatory
    }

    void setDualMode(bool enable) {
        dualModeRequested = enable;
    }

    bool isChestDetected() const { return isChestOnline; }
    bool isBaseDetected() const { return isBaseOnline; }
    bool isOperatingDual() const { return dualModeRequested && isBaseOnline; }
    bool getIsCalibrated() const { return isCalibrated; }

    float getChestOffset() const { return chestGravityOffset; }
    float getBaseOffset() const { return baseGravityOffset; }

    // Re-check sensor connection status on the fly (useful after hot-plugging wires)
    void scanSensors() {
        if (!isChestOnline) {
            chestSensor.initialize();
            isChestOnline = chestSensor.testConnection();
            if (isChestOnline) chestSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }
        if (!isBaseOnline) {
            baseSensor.initialize();
            isBaseOnline = baseSensor.testConnection();
            if (isBaseOnline) baseSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        }
    }

    void resetCalibration() {
        calChestSum = 0.0f;
        calBaseSum = 0.0f;
        calSampleCount = 0;
        isCalibrated = false;
    }

    void recordCalibrationSample() {
        if (!isChestOnline) return;

        int16_t ax1, ay1, az1;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);
        calChestSum += (float)az1 / 8192.0f;

        if (isBaseOnline) {
            int16_t ax2, ay2, az2;
            baseSensor.getAcceleration(&ax2, &ay2, &az2);
            calBaseSum += (float)az2 / 8192.0f;
        }

        calSampleCount++;
    }

    void finalizeCalibration() {
        if (calSampleCount > 0) {
            chestGravityOffset = calChestSum / (float)calSampleCount;
            if (isBaseOnline) {
                baseGravityOffset = calBaseSum / (float)calSampleCount;
            } else {
                baseGravityOffset = 0.0f;
            }
            isCalibrated = true;
        }
    }

    // 100 Hz deterministic non-blocking sampler (10,000 micros interval)
    bool sample100Hz(float& outNetAccel, uint32_t currentMicros) {
        if (currentMicros - lastSampleMicros < 10000) { // 100 Hz
            return false;
        }
        lastSampleMicros = currentMicros;

        if (!isChestOnline) {
            outNetAccel = 0.0f;
            return false;
        }

        int16_t ax1, ay1, az1;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);
        float aChest = ((float)az1 / 8192.0f) - chestGravityOffset;

        float rawNet = 0.0f;
        if (dualModeRequested && isBaseOnline) {
            int16_t ax2, ay2, az2;
            baseSensor.getAcceleration(&ax2, &ay2, &az2);
            float aBase = ((float)az2 / 8192.0f) - baseGravityOffset;
            rawNet = aChest - aBase; // Differential decoupling
        } else {
            rawNet = aChest;         // Single sensor sternal baseline
        }

        // 1st order exponential smoothing filter (alpha = 0.25 -> ~4.5 Hz lowpass cutoff)
        const float alpha = 0.25f;
        lastFilteredNetAccel = (alpha * rawNet) + ((1.0f - alpha) * lastFilteredNetAccel);
        outNetAccel = lastFilteredNetAccel;
        return true;
    }
};

#endif // BENCH_SENSORS_H
