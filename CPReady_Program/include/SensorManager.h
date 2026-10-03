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
    float calNetMin;          // Minimum raw net differential during calibration (for stability check)
    float calNetMax;          // Maximum raw net differential during calibration (for stability check)

public:
    SensorManager() 
        : chestSensor(CPReadyConfig::CHEST_MPU_I2C_ADDR), 
          baseSensor(CPReadyConfig::BASE_MPU_I2C_ADDR), 
          chestGravityOffset(0.0f), baseGravityOffset(0.0f),
          lastFilteredNetAccel(0.0f), lastSampleMicros(0),
          calChestSum(0.0f), calBaseSum(0.0f), calSampleCount(0), isCalibrated(false),
          calNetMin(999.0f), calNetMax(-999.0f) {}

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
    }

    // Called periodically during the idle baseline window
    void recordCalibrationSample() {
        int16_t ax1, ay1, az1;
        int16_t ax2, ay2, az2;
        chestSensor.getAcceleration(&ax1, &ay1, &az1);
        baseSensor.getAcceleration(&ax2, &ay2, &az2);

        calChestSum += (float)az1 / 8192.0f; // Scale factor for +/- 4g is 8192 LSB/g
        calBaseSum  += (float)az2 / 8192.0f;
        calSampleCount++;

        // Track raw differential spread for motion stability validation
        float netSample = ((float)az1 - (float)az2) / 8192.0f;
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

    // Returns true if hand motion during calibration stayed within the stability threshold (0.30g P-P)
    bool isCalibrationStable() const {
        if (calSampleCount < 10) return false;
        return (calNetMax - calNetMin) <= 0.30f;
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
