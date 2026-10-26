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
    uint8_t chestMuxChannel;
    #if USE_DUAL_MPU
    uint8_t baseMuxChannel;
    #endif
    uint8_t chestI2CAddr;
    #if USE_DUAL_MPU
    uint8_t baseI2CAddr;
    #endif
    bool hasMultiplexer;
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
    mutable uint8_t lastCalibrationFailureReason;

public:
    SensorManager() 
        : chestMuxChannel(CPReadyConfig::PCA_CHANNEL_CHEST_DEFAULT),
          #if USE_DUAL_MPU
          baseMuxChannel(CPReadyConfig::PCA_CHANNEL_BASE_DEFAULT),
          #endif
          chestI2CAddr(CPReadyConfig::CHEST_MPU_I2C_ADDR),
          #if USE_DUAL_MPU
          baseI2CAddr(CPReadyConfig::BASE_MPU_I2C_ADDR),
          #endif
          hasMultiplexer(false),
          chestGravityOffset(0.0f), baseGravityOffset(0.0f),
          lastFilteredNetAccel(0.0f), lastSampleMicros(0),
          calChestSum(0.0f), calBaseSum(0.0f), calSampleCount(0), isCalibrated(false),
          calNetMin(999.0f), calNetMax(-999.0f),
          calChestMin(999.0f), calChestMax(-999.0f),
          calBaseMin(999.0f), calBaseMax(-999.0f),
          lastCalibrationFailureReason(ERR_NONE) {}

    // Multiplexer Channel Switching Helpers (with capacitive settling delay)
    void selectMuxChannel(uint8_t channel) {
        if (!hasMultiplexer || channel > 7) return;
        Wire.beginTransmission(CPReadyConfig::PCA9548A_I2C_ADDR);
        Wire.write(1 << channel);
        Wire.endTransmission();
        delayMicroseconds(50); // Let newly connected channel bus line capacitance settle
    }

    void disableMux() {
        if (!hasMultiplexer) return;
        Wire.beginTransmission(CPReadyConfig::PCA9548A_I2C_ADDR);
        Wire.write(0x00);
        Wire.endTransmission();
        delayMicroseconds(50);
    }

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
                    Serial.print(" (MPU-6050 Default / 0x68)");
                } else if (addr == 0x69) {
                    Serial.print(" (MPU-6050 Alternate / 0x69)");
                } else if (addr == CPReadyConfig::PCA9548A_I2C_ADDR) {
                    Serial.print(" (PCA9548A I2C Multiplexer)");
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

    // Automated boot-time diagnostic scanner across all 8 downstream multiplexer channels
    void scanMultiplexerChannels() {
        if (!hasMultiplexer) return;
        Serial.println("[MUX SCAN] Probing all 8 downstream PCA9548A multiplexer channels (SD0-SD7)...");
        uint8_t totalDevicesAcrossChannels = 0;

        for (uint8_t ch = 0; ch < 8; ch++) {
            selectMuxChannel(ch);
            uint8_t chDevices = 0;

            for (uint8_t addr = 1; addr < 127; addr++) {
                // Skip the multiplexer's own address to avoid echoing upstream bus traffic
                if (addr == CPReadyConfig::PCA9548A_I2C_ADDR) continue;

                Wire.beginTransmission(addr);
                if (Wire.endTransmission() == 0) {
                    if (chDevices == 0) {
                        Serial.printf("[MUX SCAN]  -> Channel SD%d:\n", ch);
                    }
                    Serial.printf("        * Device at 0x%02X", addr);
                    if (addr == 0x68) {
                        Serial.print(" (MPU-6050 Default / 0x68)");
                    } else if (addr == 0x69) {
                        Serial.print(" (MPU-6050 Alternate / 0x69)");
                    }

                    // Query WHO_AM_I register for MPU devices
                    if (addr == 0x68 || addr == 0x69) {
                        Wire.beginTransmission(addr);
                        Wire.write(0x75);
                        if (Wire.endTransmission(false) == 0 && Wire.requestFrom((int)addr, 1) == 1) {
                            uint8_t whoAmI = Wire.read();
                            const char* tag = (whoAmI == 0x68) ? " - MPU6050 Genuine" 
                                            : (whoAmI == 0x70 || whoAmI == 0x72 ? " - MPU6500/Clone" : "");
                            Serial.printf(" [WHO_AM_I: 0x%02X%s]", whoAmI, tag);
                        }
                    }
                    Serial.println();
                    chDevices++;
                    totalDevicesAcrossChannels++;
                }
            }
        }
        disableMux();

        if (totalDevicesAcrossChannels == 0) {
            Serial.println("[MUX SCAN]  -> [WARN] No devices found across any downstream multiplexer channel!");
        } else {
            Serial.printf("[MUX SCAN]  -> Downstream scan complete: %d device(s) found across all channels.\n", totalDevicesAcrossChannels);
        }
    }

    // Dynamic PCA9548A channel scanner & automatic mapping (with multi-address & retry support)
    bool detectAndMapChannels() {
        Wire.beginTransmission(CPReadyConfig::PCA9548A_I2C_ADDR);
        if (Wire.endTransmission() != 0) {
            hasMultiplexer = false;
            return false;
        }
        hasMultiplexer = true;

        int8_t detectedChannels[8];
        uint8_t detectedAddresses[8];
        uint8_t detectedCount = 0;

        const uint8_t candidateAddrs[] = {0x68, 0x69};

        for (uint8_t ch = 0; ch < 8; ch++) {
            selectMuxChannel(ch);

            for (uint8_t a = 0; a < 2; a++) {
                uint8_t probeAddr = candidateAddrs[a];
                bool foundOnChannel = false;

                // Up to 3 retries per candidate address to reject transient contact bounce or wire noise
                for (uint8_t attempt = 0; attempt < 3; attempt++) {
                    Wire.beginTransmission(probeAddr);
                    if (Wire.endTransmission() == 0) {
                        foundOnChannel = true;
                        break;
                    }
                    delay(2);
                }

                if (foundOnChannel) {
                    detectedChannels[detectedCount] = ch;
                    detectedAddresses[detectedCount] = probeAddr;
                    detectedCount++;

                    // Query WHO_AM_I register (0x75) for diagnostic transparency
                    uint8_t whoAmI = 0x00;
                    Wire.beginTransmission(probeAddr);
                    Wire.write(0x75);
                    if (Wire.endTransmission(false) == 0) {
                        if (Wire.requestFrom((int)probeAddr, 1) == 1) {
                            whoAmI = Wire.read();
                        }
                    }

                    const char* chipTag = (whoAmI == 0x68) ? " - MPU6050 Genuine" 
                                        : (whoAmI == 0x70 || whoAmI == 0x72 ? " - MPU6500/Clone" : "");
                    Serial.printf("[I2C MUX]  -> Channel SD%d: Mapped to 0x%02X (WHO_AM_I: 0x%02X%s)\n",
                        ch, probeAddr, whoAmI, chipTag);
                    break; // Sensor found on this channel, advance to next channel
                }
            }
        }
        disableMux();

        if (detectedCount == 0) {
            Serial.println("[I2C MUX WARN] Multiplexer found, but NO MPU6050 sensors detected on any channel (SD0-SD7)!");
            return false;
        }

        // 1. Assign chest sensor channel (prefers default SD3 if detected)
        bool chestFound = false;
        for (uint8_t i = 0; i < detectedCount; i++) {
            if (detectedChannels[i] == CPReadyConfig::PCA_CHANNEL_CHEST_DEFAULT) {
                chestMuxChannel = CPReadyConfig::PCA_CHANNEL_CHEST_DEFAULT;
                chestI2CAddr = detectedAddresses[i];
                chestFound = true;
                break;
            }
        }
        if (!chestFound) {
            chestMuxChannel = detectedChannels[0];
            chestI2CAddr = detectedAddresses[0];
            Serial.printf("[I2C MUX] Chest sensor not on default SD%d; auto-mapped to SD%d (0x%02X).\n",
                CPReadyConfig::PCA_CHANNEL_CHEST_DEFAULT, chestMuxChannel, chestI2CAddr);
        } else {
            Serial.printf("[I2C MUX] Chest sensor mapped to SD%d (0x%02X).\n", chestMuxChannel, chestI2CAddr);
        }

        #if USE_DUAL_MPU
        if (detectedCount < 2) {
            Serial.printf("[I2C MUX WARN] Dual MPU mode enabled, but only %d MPU sensor detected!\n", detectedCount);
            return false;
        }

        // 2. Assign base sensor channel (prefers default SD2 if detected and not chest)
        bool baseFound = false;
        for (uint8_t i = 0; i < detectedCount; i++) {
            if (detectedChannels[i] == CPReadyConfig::PCA_CHANNEL_BASE_DEFAULT &&
                detectedChannels[i] != chestMuxChannel) {
                baseMuxChannel = CPReadyConfig::PCA_CHANNEL_BASE_DEFAULT;
                baseI2CAddr = detectedAddresses[i];
                baseFound = true;
                break;
            }
        }
        if (!baseFound) {
            for (uint8_t i = 0; i < detectedCount; i++) {
                if (detectedChannels[i] != chestMuxChannel) {
                    baseMuxChannel = detectedChannels[i];
                    baseI2CAddr = detectedAddresses[i];
                    break;
                }
            }
            Serial.printf("[I2C MUX] Base sensor not on default SD%d; auto-mapped to SD%d (0x%02X).\n",
                CPReadyConfig::PCA_CHANNEL_BASE_DEFAULT, baseMuxChannel, baseI2CAddr);
        } else {
            Serial.printf("[I2C MUX] Base sensor mapped to SD%d (0x%02X).\n", baseMuxChannel, baseI2CAddr);
        }
        #endif

        return true;
    }

    bool begin() {
        delay(50); // Power-on stabilization delay for MPU-6050 and PCA9548A internal POR
        recoverI2CBus();
        scanI2CBus();

        // Check if PCA9548A multiplexer is online at 0x70
        Wire.beginTransmission(CPReadyConfig::PCA9548A_I2C_ADDR);
        hasMultiplexer = (Wire.endTransmission() == 0);

        if (hasMultiplexer) {
            Serial.printf("[I2C MUX] PCA9548A Multiplexer detected at address 0x%02X.\n", CPReadyConfig::PCA9548A_I2C_ADDR);
            scanMultiplexerChannels();

            bool muxDetected = detectAndMapChannels();
            if (!muxDetected) {
                disableMux();
                return false;
            }

            // Initialize chest sensor behind its multiplexer channel
            selectMuxChannel(chestMuxChannel);
            if (!chestSensor.begin(chestI2CAddr, &Wire)) {
                Serial.printf("[ERROR] Failed to initialize Chest MPU6050 on Mux SD%d (address 0x%02X)!\n", 
                    chestMuxChannel, chestI2CAddr);
                disableMux();
                return false;
            }
            chestSensor.setAccelerometerRange(MPU6050_RANGE_4_G);
            chestSensor.setFilterBandwidth(MPU6050_BAND_44_HZ);

            #if USE_DUAL_MPU
            // Initialize base sensor behind its multiplexer channel
            selectMuxChannel(baseMuxChannel);
            if (!baseSensor.begin(baseI2CAddr, &Wire)) {
                Serial.printf("[ERROR] Failed to initialize Base MPU6050 on Mux SD%d (address 0x%02X)!\n", 
                    baseMuxChannel, baseI2CAddr);
                disableMux();
                return false;
            }
            baseSensor.setAccelerometerRange(MPU6050_RANGE_4_G);
            baseSensor.setFilterBandwidth(MPU6050_BAND_44_HZ);
            #endif

            disableMux();
            return true;
        } else {
            // Direct bus fallback (without multiplexer)
            #if USE_DUAL_MPU
            Serial.println("[ERROR] Dual MPU mode requires PCA9548A multiplexer at 0x70, but it was not detected!");
            return false;
            #else
            uint8_t directAddr = CPReadyConfig::CHEST_MPU_I2C_ADDR;
            Wire.beginTransmission(directAddr);
            if (Wire.endTransmission() != 0) {
                // Try alternate address 0x69
                Wire.beginTransmission(0x69);
                if (Wire.endTransmission() == 0) {
                    directAddr = 0x69;
                }
            }
            chestI2CAddr = directAddr;
            Serial.printf("[I2C] Direct bus mode (no multiplexer): initializing chest sensor at 0x%02X...\n", directAddr);
            if (!chestSensor.begin(directAddr, &Wire)) {
                return false;
            }
            chestSensor.setAccelerometerRange(MPU6050_RANGE_4_G);
            chestSensor.setFilterBandwidth(MPU6050_BAND_44_HZ);
            return true;
            #endif
        }
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
        lastCalibrationFailureReason = ERR_NONE;
    }

    // Called periodically during the idle baseline window (with optional 100 Hz rate limiting)
    bool recordCalibrationSample(uint32_t currentMicros = 0) {
        if (currentMicros > 0) {
            if (currentMicros - lastSampleMicros < CPReadyConfig::SAMPLE_INTERVAL_MICROS) {
                return false;
            }
            lastSampleMicros = currentMicros;
        }

        selectMuxChannel(chestMuxChannel);
        sensors_event_t aChest, gChest, tempChest;
        chestSensor.getEvent(&aChest, &gChest, &tempChest);
        float a1 = aChest.acceleration.z / SENSORS_GRAVITY_STANDARD;

        calChestSum += a1;
        calSampleCount++;

        // Track single-sensor extremes
        if (a1 < calChestMin) calChestMin = a1;
        if (a1 > calChestMax) calChestMax = a1;

        #if USE_DUAL_MPU
        selectMuxChannel(baseMuxChannel);
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
        return true;
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
            lastCalibrationFailureReason = ERR_LOW_SAMPLE_COUNT;
            Serial.printf("[CALIB FAIL] Sample count low: %d / %d\n", calSampleCount, CPReadyConfig::CALIBRATION_SAMPLE_COUNT);
            return false;
        }
        if ((calNetMax - calNetMin) > CPReadyConfig::CALIBRATION_MAX_NET_SPREAD_G) {
            lastCalibrationFailureReason = ERR_MOTION_UNSTABLE;
            Serial.printf("[CALIB FAIL] Net motion spread: %.2fg > %.2fg\n", (calNetMax - calNetMin), CPReadyConfig::CALIBRATION_MAX_NET_SPREAD_G);
            return false;
        }
        if ((calChestMax - calChestMin) > CPReadyConfig::CALIBRATION_MAX_CHEST_SPREAD_G) {
            lastCalibrationFailureReason = ERR_MOTION_UNSTABLE;
            Serial.printf("[CALIB FAIL] Chest motion spread: %.2fg > %.2fg\n", (calChestMax - calChestMin), CPReadyConfig::CALIBRATION_MAX_CHEST_SPREAD_G);
            return false;
        }
        if (chestGravityOffset < CPReadyConfig::CALIBRATION_GRAVITY_MIN_G || chestGravityOffset > CPReadyConfig::CALIBRATION_GRAVITY_MAX_G) {
            lastCalibrationFailureReason = ERR_GRAVITY_IMPLAUSIBLE;
            Serial.printf("[CALIB FAIL] Chest gravity implausible: %.2fg\n", chestGravityOffset);
            return false;
        }

        #if USE_DUAL_MPU
        if ((calBaseMax - calBaseMin) > CPReadyConfig::CALIBRATION_MAX_BASE_SPREAD_G) {
            lastCalibrationFailureReason = ERR_MOTION_UNSTABLE;
            Serial.printf("[CALIB FAIL] Base motion spread: %.2fg > %.2fg\n", (calBaseMax - calBaseMin), CPReadyConfig::CALIBRATION_MAX_BASE_SPREAD_G);
            return false;
        }
        if (baseGravityOffset < CPReadyConfig::CALIBRATION_GRAVITY_MIN_G || baseGravityOffset > CPReadyConfig::CALIBRATION_GRAVITY_MAX_G) {
            lastCalibrationFailureReason = ERR_GRAVITY_IMPLAUSIBLE;
            Serial.printf("[CALIB FAIL] Base gravity implausible: %.2fg\n", baseGravityOffset);
            return false;
        }
        if (fabsf(chestGravityOffset - baseGravityOffset) > CPReadyConfig::CALIBRATION_MAX_ALIGNMENT_DIFF_G) {
            lastCalibrationFailureReason = ERR_SENSOR_ALIGNMENT;
            Serial.printf("[CALIB FAIL] Tilt/pre-pressure divergence: %.2fg > %.2fg\n", 
                fabsf(chestGravityOffset - baseGravityOffset), CPReadyConfig::CALIBRATION_MAX_ALIGNMENT_DIFF_G);
            return false;
        }
        #endif

        lastCalibrationFailureReason = ERR_NONE;
        return true;
    }

    uint8_t getCalibrationFailureReason() const { return lastCalibrationFailureReason; }

    // Primary sampling function intended to run at configured rate (default 100 Hz)
    bool sample100Hz(float& outNetAccel, uint32_t currentMicros) {
        if (currentMicros - lastSampleMicros < CPReadyConfig::SAMPLE_INTERVAL_MICROS) {
            return false; // Not time yet (non-blocking)
        }
        lastSampleMicros = currentMicros;

        selectMuxChannel(chestMuxChannel);
        sensors_event_t aChest, gChest, tempChest;
        chestSensor.getEvent(&aChest, &gChest, &tempChest);
        float aChestG = (aChest.acceleration.z / SENSORS_GRAVITY_STANDARD) - chestGravityOffset;

        #if USE_DUAL_MPU
        selectMuxChannel(baseMuxChannel);
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
    bool getHasMultiplexer() const { return hasMultiplexer; }
    uint8_t getChestChannel() const { return chestMuxChannel; }
    uint8_t getChestI2CAddress() const { return chestI2CAddr; }
    #if USE_DUAL_MPU
    uint8_t getBaseChannel() const { return baseMuxChannel; }
    uint8_t getBaseI2CAddress() const { return baseI2CAddr; }
    #endif
};

#endif // SENSOR_MANAGER_H
