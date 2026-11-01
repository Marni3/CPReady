#ifndef TELEMETRY_FRAMES_H
#define TELEMETRY_FRAMES_H

// Raw accelerometer telemetry frame contract shared by the firmware and the
// Flutter decoder. Everything is packed little-endian, matching both the ESP32
// and Android.
//
// The raw stream deliberately stays accelerometer-only. It is a separate GATT
// characteristic, so the existing 16-byte metrics protocol is untouched.

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace TelemetryFrames {

constexpr uint8_t  FRAME_TYPE           = 0x10;
constexpr uint8_t  VERSION              = 1;
constexpr uint8_t  MAX_SAMPLES_PER_FRAME = 10;
constexpr uint16_t HEADER_BYTES         = 16;
constexpr uint16_t SAMPLE_BYTES         = 16;

// Header flags (byte 5).
constexpr uint8_t FLAG_STREAMING   = (1 << 0);
constexpr uint8_t FLAG_SENSOR_FAULT = (1 << 1);
constexpr uint8_t FLAG_OVERRUN     = (1 << 2);
constexpr uint8_t FLAG_CALIBRATING = (1 << 3);

#pragma pack(push, 1)

// One unfiltered accelerometer sample. Values are milli-g (1 g = 1000), which
// fits the MPU-6050's ±4 g range in an int16 without losing resolution.
struct SensorRawSample {
    uint32_t t_us;          // device micros() at the read
    int16_t  chest_mg[3];   // chest X, Y, Z
    int16_t  base_mg[3];    // base X, Y, Z
};

struct Header {
    uint8_t  type;              // FRAME_TYPE
    uint8_t  version;           // VERSION
    uint16_t frame_sequence;    // increments for every attempted frame
    uint8_t  sample_count;      // 1..MAX_SAMPLES_PER_FRAME
    uint8_t  flags;             // FLAG_*
    uint16_t stroke_count;      // firmware detector stroke count
    uint32_t first_sample_index;// 32-bit monotonic sample index
    uint16_t dropped_frames;    // cumulative send failures this session
    uint8_t  device_state;      // DeviceState value
    uint8_t  reserved;          // 0
};

#pragma pack(pop)

static_assert(sizeof(SensorRawSample) == SAMPLE_BYTES,
              "SensorRawSample must be exactly 16 bytes");
static_assert(sizeof(Header) == HEADER_BYTES,
              "Telemetry header must be exactly 16 bytes");

// Frame size for a given sample count.
inline size_t frameSize(uint8_t sampleCount) {
    return HEADER_BYTES + (size_t)sampleCount * SAMPLE_BYTES;
}

// Packs a header and its samples into out. Returns the number of bytes written,
// or 0 when the arguments or capacity are invalid.
inline size_t encodeFrame(const Header& header,
                          const SensorRawSample* samples,
                          uint8_t* out,
                          size_t outCapacity) {
    if (samples == nullptr || out == nullptr) return 0;
    if (header.sample_count == 0 ||
        header.sample_count > MAX_SAMPLES_PER_FRAME) {
        return 0;
    }
    const size_t bytes = frameSize(header.sample_count);
    if (outCapacity < bytes) return 0;
    memcpy(out, &header, HEADER_BYTES);
    memcpy(out + HEADER_BYTES, samples,
           (size_t)header.sample_count * SAMPLE_BYTES);
    return bytes;
}

} // namespace TelemetryFrames

#endif // TELEMETRY_FRAMES_H
