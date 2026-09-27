#ifndef CPR_TYPES_H
#define CPR_TYPES_H

#include <Arduino.h>
#include "CPReadyConfig.h"
#include "BLEReadings.h"

enum class DeviceState : uint8_t {
    STANDBY = 0,
    CALIBRATING = 1,
    ACTIVE_SESSION = 2,
    SESSION_PAUSED = 3,
    FAULT_ERROR = 4
};

enum class StrokeState : uint8_t {
    WAITING_FOR_DOWNSLICK = 0,
    COMPRESSING = 1,
    RECOILING = 2
};

// Inbound command packet format written to BLE Command characteristic
#pragma pack(push, 1)
struct CPRCommandPacket {
    uint8_t command_id;            // 0x01: CALIBRATE, 0x02: START, 0x03: PAUSE, 0x04: STOP
    uint8_t payload[7];            // Optional parameters or configuration flags
};
#pragma pack(pop)

#endif // CPR_TYPES_H
