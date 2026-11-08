
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
    BLECharacteristic* pTelemetryChar;
    bool isClientConnected;

    // Thread-safe FIFO queue for string commands
    QueueHandle_t commandQueue;

    // Single-thread bridge flag for disconnection events
    volatile bool hasDisconnectedFlag;

    // Commands lost because the queue was full
    volatile uint32_t droppedCommandCount;

    // Sequence number for every CPR metrics notification
    uint16_t notifySequence;

    // Research: number of trial metrics notification attempts
    uint32_t metricsPacketsSent;

    void onConnect(BLEServer* pServer) override {
        isClientConnected = true;
        hasDisconnectedFlag = false;
        Serial.println("[BLE] Client connected.");
    }

    void onDisconnect(BLEServer* pServer) override {
        isClientConnected = false;
        hasDisconnectedFlag = true;
        BLEDevice::startAdvertising();
        Serial.println("[BLE] Client disconnected. Advertising resumed.");
    }

    void onDisconnect(
        BLEServer* pServer,
        esp_ble_gatts_cb_param_t* param
    ) override {
        Serial.printf(
            "[BLE] Disconnect reason 0x%02X (conn_id=%d)\n",
            param->disconnect.reason,
            param->disconnect.conn_id
        );
    }

    // Called when Flutter writes a BLE command
    void onWrite(BLECharacteristic* pChar) override {
        String rxVal = pChar->getValue().c_str();

        if (rxVal.length() > 0 && commandQueue != nullptr) {
            char cmdBuf[64];

            size_t copyLen =
                rxVal.length() < 63 ? rxVal.length() : 63;

            memcpy(cmdBuf, rxVal.c_str(), copyLen);
            cmdBuf[copyLen] = '\0';

            if (xQueueSend(commandQueue, cmdBuf, 0) != pdTRUE) {
                droppedCommandCount =
                    droppedCommandCount + 1;
            }
        }
    }

public:
    BleManager()
        : pServer(nullptr),
          pNotifyChar(nullptr),
          pCommandChar(nullptr),
          pTelemetryChar(nullptr),
          isClientConnected(false),
          commandQueue(nullptr),
          hasDisconnectedFlag(false),
          droppedCommandCount(0),
          notifySequence(0),
          metricsPacketsSent(0) {}

    void begin(
        const char* deviceName = CPReadyConfig::BLE_DEVICE_NAME
    ) {
        if (commandQueue == nullptr) {
            commandQueue = xQueueCreate(8, 64);
        }

        BLEDevice::init(deviceName);
        BLEDevice::setMTU(CPReadyConfig::BLE_TARGET_MTU);

        pServer = BLEDevice::createServer();
        pServer->setCallbacks(this);

        BLEService* pService = pServer->createService(
            CPReadyConfig::BLE_SERVICE_UUID
        );

        // CPR metrics notification characteristic
        pNotifyChar = pService->createCharacteristic(
            CPReadyConfig::BLE_CHAR_NOTIFY_UUID,
            BLECharacteristic::PROPERTY_READ |
            BLECharacteristic::PROPERTY_NOTIFY
        );

        pNotifyChar->addDescriptor(new BLE2902());

        // Flutter command characteristic
        pCommandChar = pService->createCharacteristic(
            CPReadyConfig::BLE_CHAR_COMMAND_UUID,
            BLECharacteristic::PROPERTY_WRITE
        );

        pCommandChar->setCallbacks(this);

        // Separate raw sensor telemetry characteristic
        pTelemetryChar = pService->createCharacteristic(
            CPReadyConfig::BLE_CHAR_RAW_UUID,
            BLECharacteristic::PROPERTY_READ |
            BLECharacteristic::PROPERTY_NOTIFY
        );

        pTelemetryChar->addDescriptor(new BLE2902());

        pService->start();

        BLEAdvertising* pAdvertising =
            BLEDevice::getAdvertising();

        pAdvertising->addServiceUUID(
            CPReadyConfig::BLE_SERVICE_UUID
        );

        pAdvertising->setScanResponse(true);
        pAdvertising->setMinPreferred(0x06);

        BLEDevice::startAdvertising();
    }

    // Research: reset TX count at the beginning of a trial
    void resetTrialPacketCount() {
        metricsPacketsSent = 0;

        Serial.printf(
            "[BLE TRIAL START] Sequence before trial: %u\n",
            (unsigned)notifySequence
        );
    }

    // Research: print original trial transmission count
    void printTrialPacketSummary() const {
        Serial.printf(
            "[BLE TX FINAL] Attempted: %lu | Last Sequence: %u\n",
            (unsigned long)metricsPacketsSent,
            (unsigned)notifySequence
        );
    }

    // Transmit CPR metrics, including rate, depth, recoil,
    // CCF, compression count, and other packet fields.
    //
    // countForTrial=false is used for GET_RESULTS recovery
    // so retransmissions do not inflate research TX counts.
    bool sendPacket(
        const CPRMetricsPacket& packet,
        bool countForTrial = true
    ) {
        if (!isClientConnected ||
            pNotifyChar == nullptr ||
            pServer == nullptr) {
            return false;
        }

        if (pServer->getConnectedCount() == 0) {
            return false;
        }

        CPRMetricsPacket stamped = packet;

        // Preserve sequence tracking
        stamped.sequence = ++notifySequence;

        // Transmit the complete existing CPR metrics structure
        pNotifyChar->setValue(
            (uint8_t*)&stamped,
            sizeof(CPRMetricsPacket)
        );

        pNotifyChar->notify();

        // Count only original real-time and final-summary
        // notification attempts for the research trial.
        if (
            countForTrial &&
            (packet.packet_type == PKT_TYPE_REALTIME ||
             packet.packet_type == PKT_TYPE_FINAL_SUMMARY)
        ) {
            metricsPacketsSent++;

            if (metricsPacketsSent % 10 == 0) {
                Serial.printf(
                    "[BLE TX] Attempted: %lu | Sequence: %u\n",
                    (unsigned long)metricsPacketsSent,
                    (unsigned)stamped.sequence
                );
            }
        }

        return true;
    }

    // Transmit a 12-byte configuration report
    bool sendPacket(const CPRConfigPacket& packet) {
        if (!isClientConnected ||
            pNotifyChar == nullptr ||
            pServer == nullptr) {
            return false;
        }

        if (pServer->getConnectedCount() == 0) {
            return false;
        }

        pNotifyChar->setValue(
            (uint8_t*)&packet,
            sizeof(CPRConfigPacket)
        );

        pNotifyChar->notify();

        return true;
    }

    // Raw accelerometer telemetry on a separate characteristic
    bool sendTelemetryFrame(
        const uint8_t* data,
        size_t length
    ) {
        if (!isClientConnected ||
            pTelemetryChar == nullptr ||
            pServer == nullptr) {
            return false;
        }

        if (data == nullptr || length == 0) {
            return false;
        }

        if (pServer->getConnectedCount() == 0) {
            return false;
        }

        pTelemetryChar->setValue(
            (uint8_t*)data,
            length
        );

        pTelemetryChar->notify();

        return true;
    }

    // Return negotiated BLE ATT MTU
    uint16_t getMtu() {
        if (!isClientConnected ||
            pServer == nullptr ||
            pServer->getConnectedCount() == 0) {
            return 23;
        }

        const uint16_t mtu =
            pServer->getPeerMTU(pServer->getConnId());

        return mtu >= 23 ? mtu : 23;
    }

    // Backwards-compatible metrics transmission alias
    bool sendMetrics(const CPRMetricsPacket& packet) {
        return sendPacket(packet);
    }

    // Check whether commands are waiting
    bool hasPendingCommand() const {
        return commandQueue != nullptr &&
               uxQueueMessagesWaiting(commandQueue) > 0;
    }

    // Read the next BLE command
    String consumeCommand() {
        char cmdBuf[64] = {0};

        if (
            commandQueue != nullptr &&
            xQueueReceive(
                commandQueue,
                cmdBuf,
                0
            ) == pdTRUE
        ) {
            return String(cmdBuf);
        }

        return String();
    }

    // Retrieve and clear dropped command count
    uint32_t consumeDroppedCommandCount() {
        uint32_t dropped = droppedCommandCount;
        droppedCommandCount = 0;
        return dropped;
    }

    // Report disconnection to the main loop
    bool checkAndClearDisconnectionEvent() {
        if (hasDisconnectedFlag) {
            hasDisconnectedFlag = false;
            return true;
        }

        return false;
    }

    bool isConnected() const {
        return isClientConnected;
    }
};

#endif // BLE_MANAGER_H
