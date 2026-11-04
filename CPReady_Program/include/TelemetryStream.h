#ifndef TELEMETRY_STREAM_H
#define TELEMETRY_STREAM_H

#include <Arduino.h>

#include "BleManager.h"
#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "TelemetryFrames.h"

/**
 * Buffers raw 100 Hz accelerometer samples into fixed-size BLE frames.
 *
 * The stream is opt-in (`TELEM:1`) and off by default, so a normal practice
 * session is byte-for-byte unchanged. Frames are sized from the negotiated ATT
 * MTU; if the phone leaves the MTU at 23 the stream stays disabled rather than
 * splitting a sample across notifications.
 *
 * The Arduino BLE library's notify() returns void, so the only failure we can
 * detect here is a missing connection/subscriber. The app still counts any
 * frame or sample gaps from the sequence fields in every frame.
 */
class TelemetryStream {
public:
    void begin(BleManager* manager) {
        ble = manager;
        updateMtu();
    }

    void setEnabled(bool on) {
        if (on) {
            resetCounters();
            enabled = true;
            updateMtu();
            Serial.printf("[TELEM] Raw stream ON (MTU %u, %u samples/frame)\n",
                          (unsigned)mtu, (unsigned)samplesPerFrame);
        } else {
            if (enabled) flush();
            enabled = false;
            Serial.println("[TELEM] Raw stream OFF.");
        }
    }

    bool isEnabled() const { return enabled; }

    // Resets per-session sequence counters without changing the enabled flag.
    void resetCounters() {
        count = 0;
        frameSequence = 0;
        nextSampleIndex = 0;
        droppedFrames = 0;
    }

    void updateMtu() {
        if (ble == nullptr) return;
        const uint16_t current = ble->getMtu();
        if (current == mtu && samplesPerFrame != 0) return;
        if (count > 0) flush();
        mtu = current;
        if (mtu <= TelemetryFrames::HEADER_BYTES + 3) {
            samplesPerFrame = 0;
            return;
        }
        const uint16_t payload = mtu - 3;
        uint16_t fits = (payload - TelemetryFrames::HEADER_BYTES) /
                        TelemetryFrames::SAMPLE_BYTES;
        if (fits > CPReadyConfig::RAW_TELEMETRY_MAX_SAMPLES) {
            fits = CPReadyConfig::RAW_TELEMETRY_MAX_SAMPLES;
        }
        samplesPerFrame = (uint8_t)fits;
    }

    uint16_t getMtu() const { return mtu; }
    uint8_t getSamplesPerFrame() const { return samplesPerFrame; }
    uint16_t getDroppedFrames() const { return droppedFrames; }

    // Adds one sample. Returns true when a frame was emitted by this call.
    bool addSample(const TelemetryFrames::SensorRawSample& sample, uint16_t strokes,
                   DeviceState deviceState, uint8_t unclampedDepthMm = 0) {
        if (!enabled) return false;
        updateMtu();
        if (samplesPerFrame == 0) return false;

        strokeCount = strokes;
        state = deviceState;
        latestUnclampedDepthMm = unclampedDepthMm;
        buffer[count++] = sample;
        if (count >= samplesPerFrame) {
            return sendFrame();
        }
        return false;
    }

    // Sends a partial frame, used when the session ends or the stream is turned
    // off so the last few samples are not lost.
    void flush() {
        if (count > 0) {
            sendFrame();
        }
    }

private:
    bool sendFrame() {
        if (count == 0) return false;

        TelemetryFrames::Header header{};
        header.type = TelemetryFrames::FRAME_TYPE;
        header.version = TelemetryFrames::VERSION;
        header.frame_sequence = ++frameSequence;
        header.sample_count = count;
        header.flags = TelemetryFrames::FLAG_STREAMING;
        if (state == DeviceState::CALIBRATING) {
            header.flags |= TelemetryFrames::FLAG_CALIBRATING;
        }
        header.stroke_count = strokeCount;
        header.first_sample_index = nextSampleIndex;
        header.dropped_frames = droppedFrames;
        header.device_state = (uint8_t)state;
        header.reserved = latestUnclampedDepthMm;

        uint8_t frame[TelemetryFrames::HEADER_BYTES +
                      TelemetryFrames::MAX_SAMPLES_PER_FRAME *
                          TelemetryFrames::SAMPLE_BYTES];
        const size_t bytes = TelemetryFrames::encodeFrame(
            header, buffer, frame, sizeof(frame));

        const bool sent = bytes > 0 && ble != nullptr &&
                          ble->sendTelemetryFrame(frame, bytes);
        if (!sent) {
            ++droppedFrames;
        }

        nextSampleIndex += count;
        count = 0;
        return sent;
    }

    BleManager* ble = nullptr;
    bool enabled = false;
    uint16_t mtu = 23;
    uint8_t samplesPerFrame = 0;
    uint8_t count = 0;
    uint16_t frameSequence = 0;
    uint32_t nextSampleIndex = 0;
    uint16_t droppedFrames = 0;
    uint16_t strokeCount = 0;
    uint8_t latestUnclampedDepthMm = 0;
    DeviceState state = DeviceState::STANDBY;
    TelemetryFrames::SensorRawSample buffer[TelemetryFrames::MAX_SAMPLES_PER_FRAME] = {};
};

#endif // TELEMETRY_STREAM_H
