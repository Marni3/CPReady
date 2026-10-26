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

    void onConnect(BLEServer* pServer) override {
        isClientConnected = true;
        hasDisconnectedFlag = false;
        Serial.printf("[BLE] Client connected. Active clients: %d\n", pServer->getConnectedCount());
    }

    void onConnect(BLEServer* pServer, esp_ble_gatts_cb_param_t *param) override {
        isClientConnected = true;
        hasDisconnectedFlag = false;
        Serial.printf("[BLE] Client connected (conn_id=%d). Active clients: %d\n",
                      param->connect.conn_id, pServer->getConnectedCount());
    }

    void onDisconnect(BLEServer* pServer) override {
        if (pServer->getConnectedCount() == 0) {
            isClientConnected = false;
            hasDisconnectedFlag = true; // Signal main thread to abort any active session
            pServer->startAdvertising(); // Resume advertising immediately for re-pairing
            Serial.println("[BLE] Client disconnected. Advertising resumed.");
        } else {
            Serial.printf("[BLE] Client disconnect event, but %d client(s) still connected.\n",
                          pServer->getConnectedCount());
        }
    }

    void onDisconnect(BLEServer* pServer, esp_ble_gatts_cb_param_t *param) override {
        Serial.printf("[BLE] Client disconnect event (conn_id=%d)\n", param->disconnect.conn_id);
        if (pServer->getConnectedCount() == 0) {
            isClientConnected = false;
            hasDisconnectedFlag = true;
            pServer->startAdvertising();
            Serial.println("[BLE] All clients disconnected. Advertising resumed.");
        } else {
            Serial.printf("[BLE] Stale disconnect for conn_id=%d ignored; %d client(s) still connected.\n",
                          param->disconnect.conn_id, pServer->getConnectedCount());
        }
    }

    // Executed in FreeRTOS background task context when Flutter writes a command
    void onWrite(BLECharacteristic* pChar) override {
        std::string rxVal = pChar->getValue();
        if (rxVal.length() > 0 && commandQueue != nullptr) {
            char cmdBuf[64];
            size_t copyLen = rxVal.length() < 63 ? rxVal.length() : 63;
            memcpy(cmdBuf, rxVal.data(), copyLen);
            cmdBuf[copyLen] = '\0';
            xQueueSend(commandQueue, cmdBuf, 0);
        }
    }

public:
    BleManager() 
        : pServer(nullptr), pNotifyChar(nullptr), pCommandChar(nullptr),
          isClientConnected(false), commandQueue(nullptr), hasDisconnectedFlag(false) {}

    void begin(const char* deviceName = CPReadyConfig::BLE_DEVICE_NAME) {
        if (commandQueue == nullptr) {
            commandQueue = xQueueCreate(8, 64);
        }
        BLEDevice::init(deviceName);
        pServer = BLEDevice::createServer();
        pServer->setCallbacks(this);

        BLEService* pService = pServer->createService(CPReadyConfig::BLE_SERVICE_UUID);

        // Notify Characteristic: pushes 11-byte CPRMetricsPacket
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

    // Transmits an 11-byte binary packet (realtime, calibration, or final summary)
    bool sendPacket(const CPRMetricsPacket& packet) {
        if (!isClientConnected || pNotifyChar == nullptr || pServer == nullptr) return false;
        if (pServer->getConnectedCount() == 0) return false;
        pNotifyChar->setValue((uint8_t*)&packet, sizeof(CPRMetricsPacket));
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
