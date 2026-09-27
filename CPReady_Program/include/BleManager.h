#ifndef BLE_MANAGER_H
#define BLE_MANAGER_H

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "CPRTypes.h"
#include "CPReadyConfig.h"
#include "BLEReadings.h"

class BleManager : public BLEServerCallbacks, public BLECharacteristicCallbacks {
private:
    BLEServer* pServer;
    BLECharacteristic* pNotifyChar;
    BLECharacteristic* pCommandChar;
    bool isClientConnected;
    
    // Single-thread bridge mailbox for string commands
    volatile bool hasCommandFlag;
    char mailboxString[64];

    void onConnect(BLEServer* pServer) override {
        isClientConnected = true;
    }

    void onDisconnect(BLEServer* pServer) override {
        isClientConnected = false;
        pServer->startAdvertising(); // Resume advertising immediately
    }

    // Executed in FreeRTOS background task context when Flutter writes a command
    void onWrite(BLECharacteristic* pChar) override {
        std::string rxVal = pChar->getValue();
        if (rxVal.length() > 0 && !hasCommandFlag) {
            size_t copyLen = rxVal.length();
            if (copyLen > 63) copyLen = 63;
            memcpy((void*)mailboxString, rxVal.data(), copyLen);
            mailboxString[copyLen] = '\0';
            hasCommandFlag = true; // Signal main loop thread
        }
    }

public:
    BleManager() 
        : pServer(nullptr), pNotifyChar(nullptr), pCommandChar(nullptr),
          isClientConnected(false), hasCommandFlag(false) {
        mailboxString[0] = '\0';
    }

    void begin(const char* deviceName = CPReadyConfig::BLE_DEVICE_NAME) {
        BLEDevice::init(deviceName);
        pServer = BLEDevice::createServer();
        pServer->setCallbacks(this);

        BLEService* pService = pServer->createService(CPReadyConfig::BLE_SERVICE_UUID);

        // Notify Characteristic: pushes 8-byte CPRMetricsPacket
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

    bool sendMetrics(const CPRMetricsPacket& packet) {
        if (!isClientConnected || pNotifyChar == nullptr) return false;
        pNotifyChar->setValue((uint8_t*)&packet, sizeof(CPRMetricsPacket));
        pNotifyChar->notify();
        return true;
    }

    // Checked inside main single-threaded loop()
    bool hasPendingCommand() const { return hasCommandFlag; }

    String consumeCommand() {
        String msg = String((char*)mailboxString);
        hasCommandFlag = false; // Reset mailbox
        return msg;
    }

    bool isConnected() const { return isClientConnected; }
};

#endif // BLE_MANAGER_H
