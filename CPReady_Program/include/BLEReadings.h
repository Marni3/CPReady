#ifndef BLE_READINGS_H
#define BLE_READINGS_H

#include <Arduino.h>

/**
 * ==============================================================================
 * CPReady BLE Telemetry & Packet Specification
 * ==============================================================================
 * 
 * This file defines the exact binary packet format transmitted over Bluetooth 
 * Low Energy (BLE) from the ESP32 to the Flutter mobile application.
 * 
 * PACKET SIZE: Exactly 8 Bytes (Packed Little-Endian)
 * SERVICE UUID:        6e400001-b5a3-f393-e0a9-e50e24dcca9e
 * METRICS CHAR UUID:   6e400002-b5a3-f393-e0a9-e50e24dcca9e
 * COMMAND CHAR UUID:   6e400003-b5a3-f393-e0a9-e50e24dcca9e
 * ==============================================================================
 */

// Ensure strict 1-byte alignment across all compilers and CPU architectures
#pragma pack(push, 1)
struct CPRMetricsPacket {
    // Byte Offset 0..1: Instantaneous compression cadence in compressions per minute (cpm)
    // Target: 100 to 120 cpm
    uint16_t rate_cpm;

    // Byte Offset 2..3: Peak-to-peak compression depth in units of 0.1 mm (tenths of a millimeter)
    // Example: A value of 540 represents 54.0 mm = 5.40 cm.
    // Target: 500 to 600 (5.0 cm to 6.0 cm)
    uint16_t depth_tenths_mm;

    // Byte Offset 4: Chest recoil status flag
    // 1 = Full complete chest recoil detected (unhindered rebound)
    // 0 = Incomplete chest recoil detected (possible rescuer leaning)
    uint8_t recoil_status;

    // Byte Offset 5: Current cumulative Chest Compression Fraction (CCF)
    // Value: 0 to 100 (represents percentage: 0% to 100%)
    // Target: >= 60% (ideally > 80%)
    uint8_t ccf_percent;

    // Byte Offset 6..7: Total cumulative elapsed practice time in seconds
    // Example: 120 represents 2 minutes of practice.
    uint16_t session_elapsed_sec;
};
#pragma pack(pop)


/**
 * High-Level Human-Readable Reading Helper
 * 
 * Provides easy conversion between the packed 8-byte network packet and 
 * natural floating-point units for local display, serial debugging, and testing.
 */
struct CPRReading {
    float rate_cpm;             // Cadence in compressions/minute
    float depth_cm;             // Depth in metric centimeters
    bool  recoil_complete;      // True if full recoil was achieved
    float ccf_percentage;       // Percentage of active compression time
    uint32_t elapsed_seconds;   // Total practice session duration

    // Convert to the 8-byte network packet for BLE transmission
    CPRMetricsPacket toPacket() const {
        CPRMetricsPacket pkt;
        pkt.rate_cpm = (uint16_t)round(rate_cpm);
        pkt.depth_tenths_mm = (uint16_t)round(depth_cm * 100.0f); // cm to 0.1 mm
        pkt.recoil_status = recoil_complete ? 1 : 0;
        pkt.ccf_percent = (uint8_t)round(ccf_percentage);
        pkt.session_elapsed_sec = (uint16_t)elapsed_seconds;
        return pkt;
    }

    // Parse from an 8-byte network packet received from BLE
    static CPRReading fromPacket(const CPRMetricsPacket& pkt) {
        CPRReading r;
        r.rate_cpm = (float)pkt.rate_cpm;
        r.depth_cm = (float)pkt.depth_tenths_mm / 100.0f; // 0.1 mm to cm
        r.recoil_complete = (pkt.recoil_status == 1);
        r.ccf_percentage = (float)pkt.ccf_percent;
        r.elapsed_seconds = (uint32_t)pkt.session_elapsed_sec;
        return r;
    }

    // Format as a clean debug string for Serial Monitor output
    String toDebugString() const {
        char buf[96];
        snprintf(buf, sizeof(buf), 
            "Rate: %3.0f cpm | Depth: %4.2f cm | Recoil: %s | CCF: %3.0f%% | Time: %3ds",
            rate_cpm, depth_cm, recoil_complete ? "OK" : "LEAN", ccf_percentage, elapsed_seconds);
        return String(buf);
    }

    // Format as lightweight JSON for mobile or serial logging
    String toJson() const {
        char buf[128];
        snprintf(buf, sizeof(buf),
            "{\"rate\":%.1f,\"depth\":%.2f,\"recoil\":%s,\"ccf\":%.1f,\"time\":%d}",
            rate_cpm, depth_cm, recoil_complete ? "true" : "false", ccf_percentage, elapsed_seconds);
        return String(buf);
    }
};

/*
 ==============================================================================
 DART / FLUTTER DECODING SNIPPET (For Software / Mobile Developers)
 ==============================================================================
 
 Copy-paste this Dart parser directly into your Flutter app's BLE listener:

 ```dart
 import 'dart:typed_data';

 class CPRMetrics {
   final int rateCpm;
   final double depthCm;
   final bool recoilComplete;
   final int ccfPercent;
   final int elapsedSeconds;

   CPRMetrics({
     required this.rateCpm,
     required this.depthCm,
     required this.recoilComplete,
     required this.ccfPercent,
     required this.elapsedSeconds,
   });

   factory CPRMetrics.fromBytes(List<int> bytes) {
     if (bytes.length < 8) {
       throw ArgumentError("Invalid packet length: expected 8 bytes, got ${bytes.length}");
     }
     final byteData = ByteData.sublistView(Uint8List.fromList(bytes));

     final rate = byteData.getUint16(0, Endian.little);
     final depthTenthsMm = byteData.getUint16(2, Endian.little);
     final recoil = byteData.getUint8(4) == 1;
     final ccf = byteData.getUint8(5);
     final elapsed = byteData.getUint16(6, Endian.little);

     return CPRMetrics(
       rateCpm: rate,
       depthCm: depthTenthsMm / 100.0, // Convert 0.1 mm to cm
       recoilComplete: recoil,
       ccfPercent: ccf,
       elapsedSeconds: elapsed,
     );
   }
 }

 // Characteristic UUIDs:
 // static const String serviceUuid     = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
 // static const String metricsCharUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
 // static const String commandCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

 // Usage in flutter_blue_plus:
 // characteristic.lastValueStream.listen((value) {
 //   if (value.length >= 8) {
 //     final metrics = CPRMetrics.fromBytes(value);
 //     print("Rate: ${metrics.rateCpm} cpm, Depth: ${metrics.depthCm} cm");
 //   }
 // });
 ```
 ==============================================================================
*/

#endif // BLE_READINGS_H
