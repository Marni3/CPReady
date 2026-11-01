// Native check of the raw telemetry frame contract.
//
// Build and run from CPReady_Program/test_native:
//   g++ -std=c++17 -O2 -I ../include telemetry_frames.cpp -o telemetry_frames
//   ./telemetry_frames

#include <cstddef>
#include <cstdio>
#include <cstring>

#include "TelemetryFrames.h"

using namespace TelemetryFrames;

static int failures = 0;

static void check(bool ok, const char* what) {
    printf("[%s] %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) failures++;
}

int main() {
    check(sizeof(Header) == 16, "header is 16 bytes");
    check(sizeof(SensorRawSample) == 16, "sample is 16 bytes");
    check(frameSize(10) == 176, "10-sample frame is 176 bytes");
    check(offsetof(Header, first_sample_index) + sizeof(uint32_t) == 12,
          "first_sample_index ends at byte 12");
    check(offsetof(Header, sample_count) == 4, "sample_count is byte 4");
    check(offsetof(Header, flags) == 5, "flags is byte 5");
    check(offsetof(Header, stroke_count) == 6, "stroke_count is byte 6");
    check(offsetof(Header, first_sample_index) == 8,
          "first_sample_index is byte 8");
    check(offsetof(Header, dropped_frames) == 12, "dropped_frames is byte 12");
    check(offsetof(Header, device_state) == 14, "device_state is byte 14");
    check(offsetof(SensorRawSample, t_us) == 0, "sample time is byte 0");
    check(offsetof(SensorRawSample, chest_mg) == 4,
          "chest axes start at byte 4");
    check(offsetof(SensorRawSample, base_mg) == 10,
          "base axes start at byte 10");

    Header header{};
    header.type = FRAME_TYPE;
    header.version = VERSION;
    header.frame_sequence = 0x1234;
    header.sample_count = 2;
    header.flags = FLAG_STREAMING;
    header.stroke_count = 0x0102;
    header.first_sample_index = 0x03040506;
    header.dropped_frames = 0x0708;
    header.device_state = 2;
    header.reserved = 0;

    SensorRawSample samples[2] = {};
    samples[0].t_us = 0x11121314;
    samples[0].chest_mg[0] = 100;
    samples[0].chest_mg[1] = -200;
    samples[0].chest_mg[2] = 300;
    samples[0].base_mg[0] = -400;
    samples[0].base_mg[1] = 500;
    samples[0].base_mg[2] = -600;
    samples[1].t_us = 0x21222324;

    uint8_t frame[256] = {};
    const size_t bytes = encodeFrame(header, samples, frame, sizeof(frame));
    check(bytes == 48, "encode returns 16 + 2*16 bytes");
    check(frame[0] == FRAME_TYPE, "type lands at byte 0");
    check(frame[1] == VERSION, "version lands at byte 1");
    check(frame[2] == 0x34 && frame[3] == 0x12,
          "frame_sequence is little-endian");
    check(frame[4] == 2, "sample_count lands at byte 4");
    check(frame[8] == 0x06 && frame[9] == 0x05 && frame[10] == 0x04 &&
              frame[11] == 0x03,
          "first_sample_index is little-endian");
    check(frame[16] == 0x14 && frame[17] == 0x13 && frame[18] == 0x12 &&
              frame[19] == 0x11,
          "sample time is little-endian at byte 16");

    int16_t chest0 = 0;
    memcpy(&chest0, frame + 20, sizeof(chest0));
    check(chest0 == 100, "first chest X value survives the pack");

    check(encodeFrame(header, samples, frame, 47) == 0,
          "short output buffer is rejected");
    header.sample_count = 0;
    check(encodeFrame(header, samples, frame, sizeof(frame)) == 0,
          "zero sample count is rejected");
    header.sample_count = MAX_SAMPLES_PER_FRAME + 1;
    check(encodeFrame(header, samples, frame, sizeof(frame)) == 0,
          "more than the maximum sample count is rejected");

    printf("\n%s: %d failure(s)\n", failures == 0 ? "PASS" : "FAIL", failures);
    return failures == 0 ? 0 : 1;
}
