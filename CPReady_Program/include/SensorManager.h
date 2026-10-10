#ifndef SENSOR_MANAGER_H
#define SENSOR_MANAGER_H

#include <Wire.h>
#include <MPU6050.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"

class SensorManager {
private:
    MPU6050 chestSensor;
    MPU6050 baseSensor;
    float chestGravityOffset;
    float baseGravityOffset;
    float lastFilteredNetAccel;
    uint32_t lastSampleMicros;
    
    // Non-blocking calibration accumulators
    float calChestSum;
    float calBaseSum;
    uint16_t calSampleCount;
    bool isCalibrated;
    float calNetMin;          // Minimum raw net differential during calibration
    float calNetMax;          // Maximum raw net differential during calibration
    float calChestMin;        // Minimum raw chest reading during calibration
    float calChestMax;        // Maximum raw chest reading during calibration
    float calBaseMin;         // Minimum raw base reading during calibration
    float calBaseMax;         // Maximum raw base reading during calibration

public:
    SensorManager() 
        : chestSensor(CPReadyConfig::CHEST_MPU_I2C_ADDR), 
          baseSensor(CPReadyConfig::BASE_MPU_I2C_ADDR), 
          chestGravityOffset(0.0f), baseGravityOffset(0.0f),
          lastFilteredNetAccel(0.0f), lastSampleMicros(0),
          calChestSum(0.0f), calBaseSum(0.0f), calSampleCount(0), isCalibrated(false),
          calNetMin(999.0f), calNetMax(-999.0f),
          calChestMin(999.0f), calChestMax(-999.0f),
          calBaseMin(999.0f), calBaseMax(-999.0f) {}

    bool begin() {
        Wire.begin(CPReadyConfig::I2C_SDA_PIN, CPReadyConfig::I2C_SCL_PIN);
        Wire.setClock(CPReadyConfig::I2C_CLOCK_SPEED_HZ);
        Wire.setTimeOut(CPReadyConfig::I2C_TIMEOUT_MS);

        chestSensor.initialize();
        baseSensor.initialize();

        if (!chestSensor.testConnection() || !baseSensor.testConnection()) {
            return false;
        }

        // Set Accelerometer full-scale range to +/- 4g (CPR peaks around 2-3g)
        chestSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);
        baseSensor.setFullScaleAccelRange(MPU6050_ACCEL_FS_4);

        return true;
    }

    // Prepare non-blocking calibration state
    void resetCalibration() {
        calChestSum = 0.0f;
        calBaseSum = 0.0f;
        calSampleCount = 0;
        isCalibrated = false;
        calNetMin = 999.0f;
        calNetMax = -999.0f;
        calChestMin = 999.0f;
        calChestMax = -999.0f;
        calBaseMin = 999.0f;
        calBaseMax = -999.0f;
    }

    // Called periodically during the idle baseline window
    void recordCalibrationSample() {
        int16_t ax1, ay1, az1;
        int16_t ax2, ay2, az2;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);
        baseSensor.getAcceleration(&ax2, &ay2, &az2);

        float a1 = (float)az1 / 8192.0f; // Scale factor for +/- 4g is 8192 LSB/g
        float a2 = (float)az2 / 8192.0f;

        calChestSum += a1;
        calBaseSum  += a2;
        calSampleCount++;

        // Track single-sensor extremes
        if (a1 < calChestMin) calChestMin = a1;
        if (a1 > calChestMax) calChestMax = a1;

        if (a2 < calBaseMin) calBaseMin = a2;
        if (a2 > calBaseMax) calBaseMax = a2;

        // Track raw differential spread for motion stability validation
        float netSample = a1 - a2;
        if (netSample < calNetMin) calNetMin = netSample;
        if (netSample > calNetMax) calNetMax = netSample;
    }

    // Finalize calculated static gravity baseline
    void finalizeCalibration() {
        if (calSampleCount > 0) {
            chestGravityOffset = calChestSum / (float)calSampleCount;
            baseGravityOffset  = calBaseSum  / (float)calSampleCount;
            isCalibrated = true;
        }
    }

    // Multi-tier calibration verification: sample count, motion spread, gravity sanity, and sensor alignment
    bool isCalibrationStable() const {
        if (calSampleCount < CPReadyConfig::CALIBRATION_MIN_SAMPLE_COUNT) {
            Serial.printf("[CALIB FAIL] Sample count low: %d / %d\n", calSampleCount, CPReadyConfig::CALIBRATION_SAMPLE_COUNT);
            return false;
        }
        if ((calNetMax - calNetMin) > CPReadyConfig::CALIBRATION_MAX_NET_SPREAD_G) {
            Serial.printf("[CALIB FAIL] Net motion spread: %.2fg > %.2fg\n", (calNetMax - calNetMin), CPReadyConfig::CALIBRATION_MAX_NET_SPREAD_G);
            return false;
        }
        if ((calChestMax - calChestMin) > CPReadyConfig::CALIBRATION_MAX_CHEST_SPREAD_G) {
            Serial.printf("[CALIB FAIL] Chest motion spread: %.2fg > %.2fg\n", (calChestMax - calChestMin), CPReadyConfig::CALIBRATION_MAX_CHEST_SPREAD_G);
            return false;
        }
        if ((calBaseMax - calBaseMin) > CPReadyConfig::CALIBRATION_MAX_BASE_SPREAD_G) {
            Serial.printf("[CALIB FAIL] Base motion spread: %.2fg > %.2fg\n", (calBaseMax - calBaseMin), CPReadyConfig::CALIBRATION_MAX_BASE_SPREAD_G);
            return false;
        }
        if (chestGravityOffset < CPReadyConfig::CALIBRATION_GRAVITY_MIN_G || chestGravityOffset > CPReadyConfig::CALIBRATION_GRAVITY_MAX_G) {
            Serial.printf("[CALIB FAIL] Chest gravity implausible: %.2fg\n", chestGravityOffset);
            return false;
        }
        if (baseGravityOffset < CPReadyConfig::CALIBRATION_GRAVITY_MIN_G || baseGravityOffset > CPReadyConfig::CALIBRATION_GRAVITY_MAX_G) {
            Serial.printf("[CALIB FAIL] Base gravity implausible: %.2fg\n", baseGravityOffset);
            return false;
        }
        if (fabsf(chestGravityOffset - baseGravityOffset) > CPReadyConfig::CALIBRATION_MAX_ALIGNMENT_DIFF_G) {
            Serial.printf("[CALIB FAIL] Tilt/pre-pressure divergence: %.2fg > %.2fg\n", 
                fabsf(chestGravityOffset - baseGravityOffset), CPReadyConfig::CALIBRATION_MAX_ALIGNMENT_DIFF_G);
            return false;
        }
        return true;
    }

    // Primary sampling function intended to run at configured rate (default 100 Hz)
    bool sample100Hz(float& outNetAccel, uint32_t currentMicros) {
        if (currentMicros - lastSampleMicros < CPReadyConfig::SAMPLE_INTERVAL_MICROS) {
            return false; // Not time yet (non-blocking)
        }
        lastSampleMicros = currentMicros;

        int16_t ax1, ay1, az1;
        int16_t ax2, ay2, az2;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);
        baseSensor.getAcceleration(&ax2, &ay2, &az2);

        float aChest = ((float)az1 / 8192.0f) - chestGravityOffset;
        float aBase  = ((float)az2 / 8192.0f) - baseGravityOffset;

        // Differential subtraction: removes table/floor mattress displacement
        float rawNet = aChest - aBase;

        // Low-pass exponential smoothing filter
        const float alpha = CPReadyConfig::LOWPASS_FILTER_ALPHA;
        lastFilteredNetAccel = (alpha * rawNet) + ((1.0f - alpha) * lastFilteredNetAccel);
        outNetAccel = lastFilteredNetAccel;
        return true;
    }

    bool getIsCalibrated() const { return isCalibrated; }
};

#endif // SENSOR_MANAGER_H
