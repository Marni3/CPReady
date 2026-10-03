# CPReady Medical Test Bench & Calibration Portal

A single-file testing and calibration sketch for **CPReady** student researchers.  
This tool allows you to test, calibrate, and validate the four American Heart Association (AHA) CPR indicators directly on your manikin **without needing Bluetooth Low Energy (BLE) or the mobile application**.

---

## 1. Features
- **Single-File Simplicity**: Everything is self-contained in `CPReady_Test_Bench.ino`. Just open and upload in Arduino IDE!
- **Open Wi-Fi Hotspot**: No password required. Connect instantly from any smartphone or laptop to `CPReady-TestBench`.
- **Mobile Medical Dashboard**: Clean, clinical white-and-blue interface with high-contrast gauges for **Rate**, **Depth**, **Chest Recoil**, and **CCF %** updating at 10 Hz.
- **Zero-Overhead Web Voice Coach**: The phone automatically speaks clinical voice prompts (*"Push harder"*, *"Release completely"*, *"Speed up"*, *"Good compressions"*) out loud through its speaker without burdening the ESP32 processor or memory.
- **Single vs. Dual MPU Toggle**: Switch between **Single-Sensor Mode (Chest Only)** and **Dual-Sensor Mode (Differential Decoupling)** with one tap.
- **Safe Flash Memory Persistence**: Protects ESP32 Flash memory with dirty-checking and a 5-second rate limiter to prevent flash memory wear ("frying" the NVS).
- **One-Click Paper Export**: Generates the exact C++ configuration block to copy directly into your research paper methodology or final firmware!

---

## 2. Hardware Wiring Guide

Connect your ESP32 to the sensors and buzzer using the pinout below:

| Component | Component Pin | ESP32 Pin | Notes |
| :--- | :--- | :--- | :--- |
| **Primary Chest MPU6050** | VCC | 3.3V | Primary motion sensor (sternum) |
| | GND | GND | Ground return |
| | SDA | GPIO 21 | Shared I2C Data bus |
| | SCL | GPIO 22 | Shared I2C Clock bus |
| | AD0 | **GND** | Sets I2C Address to **`0x68`** |
| **Spine Base MPU6050 (Optional)** | VCC | 3.3V | Reference sensor (mattress bounce) |
| | GND | GND | Ground return |
| | SDA | GPIO 21 | Connected to same SDA pin |
| | SCL | GPIO 22 | Connected to same SCL pin |
| | AD0 | **3.3V** | Sets I2C Address to **`0x69`** |
| **Piezo Buzzer** | Positive (+) | GPIO 25 | Audio metronome and state beeps |
| | Negative (-) | GND | Ground return |

> [!TIP]
> **Testing with only 1 MPU?** Simply connect the Chest MPU (`AD0` to GND). The system will automatically detect that the second sensor is missing and run in Single-MPU mode.

---

## 3. How to Open & Flash in Arduino IDE

### Step 1: Install Arduino IDE & ESP32 Board Package
1. Download and install **Arduino IDE** (version 2.0+ recommended) from [arduino.cc](https://www.arduino.cc/en/software).
2. Go to **File $\rightarrow$ Preferences**, and in "Additional Boards Manager URLs", add:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. Open **Tools $\rightarrow$ Board $\rightarrow$ Boards Manager**, search for `esp32`, and click **Install**.

### Step 2: Install the MPU6050 Library
1. In Arduino IDE, open **Tools $\rightarrow$ Manage Libraries...** (or press `Ctrl + Shift + I`).
2. Search for: `MPU6050 by Electronic Cats`.
3. Click **Install**.
*(All other libraries like WiFi, WebServer, Wire, and Preferences are already built into the ESP32 core!)*

### Step 3: Flash the ESP32
1. Open the file `CPReady_Test_Bench/CPReady_Test_Bench.ino`.
2. Under **Tools $\rightarrow$ Board**, select **ESP32 Dev Module**.
3. Under **Tools $\rightarrow$ Port**, select the COM port of your ESP32.
4. Click the **Upload** button (arrow pointing right).

---

## 4. How to Use the Web Portal

1. **Connect to Wi-Fi**:
   - On your phone or laptop, open Wi-Fi settings.
   - Connect to the open network: **`CPReady-TestBench`** (no password required).
   - *On most iPhones and Android phones, the portal will automatically pop up on your screen!*
2. **Open the Dashboard**:
   - If it doesn't pop up automatically, open your mobile browser and navigate to:
     👉 **`http://192.168.4.1`** (or `http://cpready.local`)
3. **Calibrate Baseline**:
   - Rest your hands still on the chest pad without pushing down.
   - Tap the blue **"Calibrate (2s)"** button. (If you forget and tap "Start Test", the system will automatically run this 2-second calibration first to ensure accuracy!).
   - The buzzer will beep **once**. Keep your hands still for 2 seconds.
   - The buzzer will beep **twice** when ready.
4. **Begin Test Compressions**:
   - Tap **"Start Test"** and begin compressions on your manikin.
   - Observe live metrics:
     - **Rate**: Stays in the green zone when at 100–120 cpm.
     - **Depth**: Reaches 5.0–6.0 cm.
     - **Recoil**: Displays `FULL RELEASE` in green. If leaning occurs, it alerts `LEANING / INCOMPLETE`.
     - **CCF %**: Displays active compression time fraction ($\ge 60\%$).
   - **Live Voice Coaching**: Your phone will play an alert ping and speak out loud if depth, recoil, or rate drifts out of range for 3 consecutive strokes, or praise you (*"Good compressions"*) after 15 seconds of compliant CPR. You can mute/unmute at any time using the voice toggle button.

---

## 5. NVS Flash-Wear Safeguard Audit

To prevent accidental flash memory wear ("frying" the ESP32 Flash):
- **Runtime sliders only update variables in RAM**.
- Flash is only written when you explicitly tap **"Save Settings to Memory"**.
- The firmware automatically skips writing if the values haven't changed (dirty checking).
- A 5-second rate limiter blocks rapid accidental re-saving.
