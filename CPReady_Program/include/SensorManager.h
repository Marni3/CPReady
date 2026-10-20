#ifndef SENSOR_MANAGER_H
#define SENSOR_MANAGER_H

#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"

class SensorManager {
private:
    Adafruit_MPU6050 chestSensor;
    #if USE_DUAL_MPU
    Adafruit_MPU6050 baseSensor;
    #endif
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
        : chestGravityOffset(0.0f), baseGravityOffset(0.0f),
          lastFilteredNetAccel(0.0f), lastSampleMicros(0),
          calChestSum(0.0f), calBaseSum(0.0f), calSampleCount(0), isCalibrated(false),
          calNetMin(999.0f), calNetMax(-999.0f),
          calChestMin(999.0f), calChestMax(-999.0f),
          calBaseMin(999.0f), calBaseMax(-999.0f) {}

    // Hardware I2C bus recovery routine (NXP UM10204 9-clock cycle sequence)
    // Toggles SCL up to 9 times to force any stuck slave to release SDA,
    // followed by generating a manual STOP condition before restarting Wire.
    static void recoverI2CBus() {
        Wire.end();
        pinMode(CPReadyConfig::I2C_SDA_PIN, INPUT_PULLUP);
        pinMode(CPReadyConfig::I2C_SCL_PIN, OUTPUT);
        digitalWrite(CPReadyConfig::I2C_SCL_PIN, HIGH);
        delayMicroseconds(5);

        for (int i = 0; i < 9; i++) {
            if (digitalRead(CPReadyConfig::I2C_SDA_PIN) == HIGH) {
                break; // Slave released SDA line
            }
            digitalWrite(CPReadyConfig::I2C_SCL_PIN, LOW);
            delayMicroseconds(5);
            digitalWrite(CPReadyConfig::I2C_SCL_PIN, HIGH);
            delayMicroseconds(5);
        }

        // Generate explicit STOP condition (SDA low while SCL high, then SDA high)
        pinMode(CPReadyConfig::I2C_SDA_PIN, OUTPUT);
        digitalWrite(CPReadyConfig::I2C_SDA_PIN, LOW);
        delayMicroseconds(5);
        digitalWrite(CPReadyConfig::I2C_SCL_PIN, HIGH);
        delayMicroseconds(5);
        digitalWrite(CPReadyConfig::I2C_SDA_PIN, HIGH);
        delayMicroseconds(5);

        pinMode(CPReadyConfig::I2C_SDA_PIN, INPUT_PULLUP);
        pinMode(CPReadyConfig::I2C_SCL_PIN, INPUT_PULLUP);

        Wire.begin(CPReadyConfig::I2C_SDA_PIN, CPReadyConfig::I2C_SCL_PIN);
        Wire.setClock(CPReadyConfig::I2C_CLOCK_SPEED_HZ);
        Wire.setTimeOut(CPReadyConfig::I2C_TIMEOUT_MS);
    }

    // Automated boot-time I2C bus diagnostic scanner
    static void scanI2CBus() {
        Serial.printf("[I2C SCAN] Probing I2C bus (SDA=GPIO%d, SCL=GPIO%d, Speed=%d Hz)...\n",
            CPReadyConfig::I2C_SDA_PIN, CPReadyConfig::I2C_SCL_PIN, CPReadyConfig::I2C_CLOCK_SPEED_HZ);
        uint8_t count = 0;
        for (uint8_t addr = 1; addr < 127; addr++) {
            Wire.beginTransmission(addr);
            uint8_t error = Wire.endTransmission();
            if (error == 0) {
                Serial.printf("[I2C SCAN]  -> Device detected at address 0x%02X", addr);
                if (addr == 0x68) {
                    Serial.print(" (Default MPU-6050 / Chest)");
                } else if (addr == 0x69) {
                    Serial.print(" (Alternate MPU-6050 / Base or AD0 HIGH)");
                }
                Serial.println();
                count++;
            }
        }
        if (count == 0) {
            Serial.println("[I2C SCAN]  -> [WARN] No I2C devices found! Check VCC/5V power, GND, and SDA/SCL wires.");
        } else {
            Serial.printf("[I2C SCAN]  -> Scan complete: %d device(s) found.\n", count);
        }
    }

    bool begin() {
        recoverI2CBus();
        scanI2CBus();

        if (!chestSensor.begin(CPReadyConfig::CHEST_MPU_I2C_ADDR, &Wire)) {
            return false;
        }
        chestSensor.setAccelerometerRange(MPU6050_RANGE_4_G);
        chestSensor.setFilterBandwidth(MPU6050_BAND_44_HZ);

        #if USE_DUAL_MPU
        if (!baseSensor.begin(CPReadyConfig::BASE_MPU_I2C_ADDR, &Wire)) {
            return false;
        }
        baseSensor.setAccelerometerRange(MPU6050_RANGE_4_G);
        baseSensor.setFilterBandwidth(MPU6050_BAND_44_HZ);
        #endif

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
        sensors_event_t aChest, gChest, tempChest;
        chestSensor.getEvent(&aChest, &gChest, &tempChest);
        float a1 = aChest.acceleration.z / SENSORS_GRAVITY_STANDARD;

        calChestSum += a1;
        calSampleCount++;

        // Track single-sensor extremes
        if (a1 < calChestMin) calChestMin = a1;
        if (a1 > calChestMax) calChestMax = a1;

        #if USE_DUAL_MPU
        sensors_event_t aBase, gBase, tempBase;
        baseSensor.getEvent(&aBase, &gBase, &tempBase);
        float a2 = aBase.acceleration.z / SENSORS_GRAVITY_STANDARD;

        calBaseSum  += a2;

        if (a2 < calBaseMin) calBaseMin = a2;
        if (a2 > calBaseMax) calBaseMax = a2;

        float netSample = -(a1 - a2);
        #else
        float netSample = -a1;
        #endif

        // Track raw differential spread for motion stability validation
        if (netSample < calNetMin) calNetMin = netSample;
        if (netSample > calNetMax) calNetMax = netSample;
    }

    // Finalize calculated static gravity baseline
    void finalizeCalibration() {
        if (calSampleCount > 0) {
            chestGravityOffset = calChestSum / (float)calSampleCount;
            #if USE_DUAL_MPU
            baseGravityOffset  = calBaseSum  / (float)calSampleCount;
            #else
            baseGravityOffset  = 0.0f;
            #endif
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
        if (chestGravityOffset < CPReadyConfig::CALIBRATION_GRAVITY_MIN_G || chestGravityOffset > CPReadyConfig::CALIBRATION_GRAVITY_MAX_G) {
            Serial.printf("[CALIB FAIL] Chest gravity implausible: %.2fg\n", chestGravityOffset);
            return false;
        }

        #if USE_DUAL_MPU
        if ((calBaseMax - calBaseMin) > CPReadyConfig::CALIBRATION_MAX_BASE_SPREAD_G) {
            Serial.printf("[CALIB FAIL] Base motion spread: %.2fg > %.2fg\n", (calBaseMax - calBaseMin), CPReadyConfig::CALIBRATION_MAX_BASE_SPREAD_G);
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
        #endif

        return true;
    }

    // Primary sampling function intended to run at configured rate (default 100 Hz)
    bool sample100Hz(float& outNetAccel, uint32_t currentMicros) {
        if (currentMicros - lastSampleMicros < CPReadyConfig::SAMPLE_INTERVAL_MICROS) {
            return false; // Not time yet (non-blocking)
        }
        lastSampleMicros = currentMicros;

        sensors_event_t aChest, gChest, tempChest;
        chestSensor.getEvent(&aChest, &gChest, &tempChest);
        float aChestG = (aChest.acceleration.z / SENSORS_GRAVITY_STANDARD) - chestGravityOffset;

        #if USE_DUAL_MPU
        sensors_event_t aBase, gBase, tempBase;
        baseSensor.getEvent(&aBase, &gBase, &tempBase);
        float aBaseG  = (aBase.acceleration.z / SENSORS_GRAVITY_STANDARD) - baseGravityOffset;
        float rawNet  = -(aChestG - aBaseG);
        #else
        float rawNet  = -aChestG;
        #endif

        // Low-pass exponential smoothing filter
        const float alpha = CPReadyConfig::LOWPASS_FILTER_ALPHA;
        lastFilteredNetAccel = (alpha * rawNet) + ((1.0f - alpha) * lastFilteredNetAccel);
        outNetAccel = lastFilteredNetAccel;
        return true;
    }

    bool getIsCalibrated() const { return isCalibrated; }
};

#endif // SENSOR_MANAGER_H
