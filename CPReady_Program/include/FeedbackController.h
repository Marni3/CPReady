#ifndef FEEDBACK_CONTROLLER_H
#define FEEDBACK_CONTROLLER_H

#include <Arduino.h>
#include "CPReadyConfig.h"

class FeedbackController {
private:
    uint8_t pin;
    uint32_t nextToggleMillis;
    uint8_t beepsRemaining;
    bool isBuzzerHigh;
    uint16_t onDurationMs;
    uint16_t offDurationMs;

public:
    FeedbackController() 
        : pin(CPReadyConfig::BUZZER_PIN), nextToggleMillis(0), beepsRemaining(0),
          isBuzzerHigh(false), onDurationMs(120), offDurationMs(100) {}

    void begin(uint8_t buzzerPin = CPReadyConfig::BUZZER_PIN) {
        pin = buzzerPin;
        pinMode(pin, OUTPUT);
        digitalWrite(pin, LOW);
    }

    // Completely non-blocking pattern sequencer called every loop()
    void update(uint32_t currentMillis) {
        if (beepsRemaining == 0 && !isBuzzerHigh) {
            return;
        }

        if (currentMillis >= nextToggleMillis) {
            if (isBuzzerHigh) {
                digitalWrite(pin, LOW);
                isBuzzerHigh = false;
                beepsRemaining--;
                nextToggleMillis = currentMillis + offDurationMs;
            } else if (beepsRemaining > 0) {
                digitalWrite(pin, HIGH);
                isBuzzerHigh = true;
                nextToggleMillis = currentMillis + onDurationMs;
            }
        }
    }

    // Trigger arbitrary number of distinct beeps non-blockingly
    void playBeeps(uint8_t count, uint16_t onMs = 120, uint16_t offMs = 100) {
        beepsRemaining = count;
        onDurationMs = onMs;
        offDurationMs = offMs;
        digitalWrite(pin, HIGH);
        isBuzzerHigh = true;
        nextToggleMillis = millis() + onDurationMs;
    }

    // Protocol Step 1: Buzzes ONCE when calibration measurements start
    void playCalibrationStart() {
        playBeeps(1, CPReadyConfig::BEEP_CALIB_START_ON_MS, CPReadyConfig::BEEP_CALIB_START_OFF_MS);
    }

    // Protocol Step 2: Buzzes TWICE when calibration is done and compressions should begin
    void playCompressionsBegin() {
        playBeeps(2, CPReadyConfig::BEEP_COMPRESS_BEGIN_ON_MS, CPReadyConfig::BEEP_COMPRESS_BEGIN_OFF_MS);
    }

    // Protocol Step 3: Buzzes THREE times when CPR practice session is completed
    void playSessionComplete() {
        playBeeps(3, CPReadyConfig::BEEP_SESSION_COMPLETE_ON_MS, CPReadyConfig::BEEP_SESSION_COMPLETE_OFF_MS);
    }

    // Quick metronome tick during active compressions (30 ms click)
    void playMetronomeTick() {
        if (beepsRemaining == 0) {
            playBeeps(1, CPReadyConfig::BEEP_METRONOME_CLICK_MS, CPReadyConfig::BEEP_METRONOME_CLICK_MS);
        }
    }

    // Immediately stop buzzer and clear pending beep queue (e.g. on disconnect or reset)
    void abort() {
        digitalWrite(pin, LOW);
        isBuzzerHigh = false;
        beepsRemaining = 0;
        nextToggleMillis = 0;
    }
};

#endif // FEEDBACK_CONTROLLER_H
