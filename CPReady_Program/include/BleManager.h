#ifndef BLE_MANAGER_H
#define BLE_MANAGER_H

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"

#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

class BleManager : public BLEServerCallbacks, public BLECharacteristicCallbacks {
private:
    BLEServer* pServer;
    BLECharacteristic* pNotifyChar;
    BLECharacteristic* pCommandChar;
    bool isClientConnected;
    
    // Thread-safe FIFO queue for string commands
    QueueHandle_t commandQueue;

    // Single-thread bridge flag for disconnection events
    volatile bool hasDisconnectedFlag;

    // Commands lost because the queue was full (reported from the main loop)
    volatile uint32_t droppedCommandCount;

    // Sequence number stamped into every metrics notification, so the app can count lost packets
    uint16_t notifySequence;

    void onConnect(BLEServer* pServer) override {
        isClientConnected = true;
        hasDisconnectedFlag = false;
        Serial.println("[BLE] Client connected.");
    }

    // Arduino-ESP32 calls onDisconnect() BEFORE it decrements the connected count, so
    // getConnectedCount() still includes the departing client here. CPReady only ever
    // has one client, so every disconnect is "the" disconnect: always resume advertising.
    void onDisconnect(BLEServer* pServer) override {
        isClientConnected = false;
        hasDisconnectedFlag = true; // Signal main thread to abort any active session
        BLEDevice::startAdvertising(); // Resume advertising immediately for re-pairing
        Serial.println("[BLE] Client disconnected. Advertising resumed.");
    }

    void onDisconnect(BLEServer* pServer, esp_ble_gatts_cb_param_t *param) override {
        // Both overloads are invoked; this one only adds the reason to the log.
        Serial.printf("[BLE] Disconnect reason 0x%02X (conn_id=%d)\n",
                      param->disconnect.reason, param->disconnect.conn_id);
    }

    // Executed in FreeRTOS background task context when Flutter writes a command
    void onWrite(BLECharacteristic* pChar) override {
        // Universal cross-version extraction: works on both Arduino-ESP32 v2.x (std::string) and v3.x (String)
        String rxVal = pChar->getValue().c_str();
        if (rxVal.length() > 0 && commandQueue != nullptr) {
            char cmdBuf[64];
            size_t copyLen = rxVal.length() < 63 ? rxVal.length() : 63;
            memcpy(cmdBuf, rxVal.c_str(), copyLen);
            cmdBuf[copyLen] = '\0';
            if (xQueueSend(commandQueue, cmdBuf, 0) != pdTRUE) {
                droppedCommandCount = droppedCommandCount + 1;
            }
        }
    }

public:
    BleManager()
        : pServer(nullptr), pNotifyChar(nullptr), pCommandChar(nullptr),
          isClientConnected(false), commandQueue(nullptr), hasDisconnectedFlag(false),
          droppedCommandCount(0), notifySequence(0) {}

    void begin(const char* deviceName = CPReadyConfig::BLE_DEVICE_NAME) {
        if (commandQueue == nullptr) {
            commandQueue = xQueueCreate(8, 64);
        }
        BLEDevice::init(deviceName);
        pServer = BLEDevice::createServer();
        pServer->setCallbacks(this);

        BLEService* pService = pServer->createService(CPReadyConfig::BLE_SERVICE_UUID);

        // Notify Characteristic: pushes the 16-byte CPRMetricsPacket and 12-byte config report
        pNotifyChar = pService->createCharacteristic(
            CPReadyConfig::BLE_CHAR_NOTIFY_UUID,
            BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
        );
        pNotifyChar->addDescriptor(new BLE2902());

        // Command Characteristic: Flutter app writes text commands here (e.g. "START", "STOP")
        pCommandChar = pService->createCharacteristic(
            CPReadyConfig::BLE_CHAR_COMMAND_UUID,
            BLECharacteristic::PROPERTY_WRITE
        );
        pCommandChar->setCallbacks(this);

        pService->start();
        BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
        pAdvertising->addServiceUUID(CPReadyConfig::BLE_SERVICE_UUID);
        pAdvertising->setScanResponse(true);
        pAdvertising->setMinPreferred(0x06);
        BLEDevice::startAdvertising();
    }

    // Transmits a 16-byte metrics packet (realtime, calibration, error or final summary),
    // stamped with the next sequence number.
    bool sendPacket(const CPRMetricsPacket& packet) {
        if (!isClientConnected || pNotifyChar == nullptr || pServer == nullptr) return false;
        if (pServer->getConnectedCount() == 0) return false;
        CPRMetricsPacket stamped = packet;
        stamped.sequence = ++notifySequence;
        pNotifyChar->setValue((uint8_t*)&stamped, sizeof(CPRMetricsPacket));
        pNotifyChar->notify();
        return true;
    }

    // Transmits a 12-byte Type 6 configuration report packet
    bool sendPacket(const CPRConfigPacket& packet) {
        if (!isClientConnected || pNotifyChar == nullptr || pServer == nullptr) return false;
        if (pServer->getConnectedCount() == 0) return false;
        pNotifyChar->setValue((uint8_t*)&packet, sizeof(CPRConfigPacket));
        pNotifyChar->notify();
        return true;
    }

    // Backwards-compatible alias for existing code
    bool sendMetrics(const CPRMetricsPacket& packet) {
        return sendPacket(packet);
    }

    // Checked inside main single-threaded loop()
    bool hasPendingCommand() const {
        return commandQueue != nullptr && (uxQueueMessagesWaiting(commandQueue) > 0);
    }

    String consumeCommand() {
        char cmdBuf[64] = {0};
        if (commandQueue != nullptr && xQueueReceive(commandQueue, cmdBuf, 0) == pdTRUE) {
            return String(cmdBuf);
        }
        return String();
    }

    // Returns and clears the number of commands dropped because the queue was full
    uint32_t consumeDroppedCommandCount() {
        uint32_t dropped = droppedCommandCount;
        droppedCommandCount = 0;
        return dropped;
    }

    // Checked inside main loop() to abort active session on disconnection
    bool checkAndClearDisconnectionEvent() {
        if (hasDisconnectedFlag) {
            hasDisconnectedFlag = false;
            return true;
        }
        return false;
    }

    bool isConnected() const { return isClientConnected; }
};

#endif // BLE_MANAGER_H
