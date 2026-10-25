# CPReady Hardware Testing, Calibration & Parameter Tuning Guide

**Target Audience**: Testing Team, Capstone Evaluators & Lab Assistants  
**Hardware Setup**: ESP32 Dev Module + PCA9548A I2C Multiplexer + Dual MPU-6050 Accelerometers  
**Firmware Configuration File**: `CPReady_Program/include/CPReadyConfig.h`  

---

## 1. Introduction: How the System Works (In Plain English)

The CPReady vest measures how well a rescuer performs cardiopulmonary resuscitation (CPR) on a training manikin. To do this accurately, it uses **two motion sensors (MPU-6050 / MPU-6500s)** connected through a small traffic controller chip called the **PCA9548A Multiplexer**:

1. **Chest Sensor (MPU 1 on SD3)**: Mounted on the handpiece over the manikin's sternum. It moves up and down directly with your hands.
2. **Base / Spine Sensor (MPU 2 on SD2)**: Placed flat beneath the manikin's back. It stays still on the table or floor.
3. **The Multiplexer (PCA9548A at address `0x70`)**: Because both motion sensors share the same hardware address (`0x68`), the multiplexer acts as an automatic switch, letting the ESP32 talk to the Chest sensor first, then the Base sensor, without any bus collision.

### The Differential Motion Secret
When you push hard on a training manikin resting on a table, the table or mattress flexes slightly. If we only measured the chest sensor, table bounce would trick the system into thinking you compressed deeper than you actually did. 

By subtracting the spine movement from the chest movement:
```
Actual Compression = Chest Movement - Table/Spine Movement
```
Any room vibration or mattress flexing is automatically canceled out!

---

## 2. Where to Click: PlatformIO & File Navigation

You do **not** need to edit code files for standard testing. Parameters can be tuned **directly through the mobile app** or updated in configuration:

```
+-------------------------------------------------------------------------+
| [File Explorer]                                                         |
|  v CPReady_Program                                                      |
|    > docs                                                               |
|        CALIBRATION_AND_TUNING_GUIDE.md <-- You are here!                |
|    v include                                                            |
|        BLEReadings.h                                                    |
|        CPRTypes.h                                                       |
|      * CPReadyConfig.h  <-- Hardcoded defaults (NVS overrides these)    |
|        CompressionTracker.h                                             |
|        SensorManager.h                                                  |
|    > lib                                                                |
|        Adafruit_MPU6050  <-- Patched for MPU6500 & Clone dies (0x70)   |
|    > src                                                                |
|        main.cpp                                                         |
|      platformio.ini                                                     |
+-------------------------------------------------------------------------+
| Bottom Blue Bar:  [Build (✔ Checkmark)]  [Upload (➔ Right Arrow)]  [Monitor]|
+-------------------------------------------------------------------------+
```

### The 3 Key Buttons on the Bottom Status Bar
1. **Build (✔ Checkmark icon)**: Compiles the firmware to verify syntax and library dependencies without flashing hardware.
2. **Upload (➔ Right Arrow icon)**: Flashes firmware into the ESP32 via your USB cable.
3. **Serial Monitor (Plug icon or `Ctrl + Alt + S`)**: Opens real-time diagnostics at **115200 baud**.

---

## 3. Phase 1: First-Time Hardware Bench Check

### Step 1: Physical Sensor Orientation
- Both MPU sensor boards must be oriented with the **black square chip facing UP towards the ceiling**.
- If a sensor is upside-down or severely tilted, gravity will read negative or skewed, and the firmware will reject the baseline during calibration.

### Step 2: Plug In & Check Startup Messages
1. Connect the ESP32 via USB and open Serial Monitor at `115200` baud.
2. Press the **EN / RST** button on the ESP32 to reboot it.
3. Verify the output matches:

```text
=========================================
     CPReady Firmware Initializing       
=========================================
[NVS] Flash configuration loaded: Profile=MANIKIN_STANDARD | Depth K=11.20
[I2C SCAN] Probing I2C bus (SDA=GPIO21, SCL=GPIO22, Speed=100000 Hz)...
[I2C SCAN]  -> Device detected at address 0x70 (PCA9548A I2C Multiplexer)
[I2C MUX] PCA9548A Multiplexer detected at address 0x70.
[MUX SCAN] Probing all 8 downstream PCA9548A multiplexer channels (SD0-SD7)...
        * Device at 0x68 (MPU-6050 Default / 0x68) [WHO_AM_I: 0x70 - MPU6500/Clone]
[MUX SCAN]  -> Downstream scan complete: 2 device(s) found across all channels.
[I2C MUX]  -> Channel SD2: Mapped to 0x68 (WHO_AM_I: 0x70 - MPU6500/Clone)
[I2C MUX]  -> Channel SD3: Mapped to 0x68 (WHO_AM_I: 0x70 - MPU6500/Clone)
[I2C MUX] Chest sensor mapped to SD3 (0x68).
[I2C MUX] Base sensor mapped to SD2 (0x68).
[OK] Dual-MPU mode initialized via PCA9548A: Chest on SD3 (0x68), Base on SD2 (0x68).
[OK] BLE GATT Server Advertising as 'CPReady'. Ready for app connection.
```

---

## 4. Phase 2: Stationary Baseline Calibration (Hands at Rest)

Before compressions begin, the system must capture static gravity. Sending `"CALIBRATE"` triggers this:
- The rescuer rests hands lightly on the chest handpiece without pushing down.
- The vest measures resting baseline for **2.0 seconds** (200 samples).
- On success, Packet Type 3 is broadcast, enabling the *"Begin Session"* button!

| Serial Error Message | What It Means in Plain English | Practical Fix |
| :--- | :--- | :--- |
| `[CALIB FAIL] Sample count low: X / 200` | Sensor wire disconnected mid-sample. | Check DuPont jumpers or ensure I2C clock is 100 kHz. |
| `[CALIB FAIL] Net motion spread: 0.45g > 0.30g` | Rescuer trembling or table bumped during the 2s window. | Keep hands completely still until the countdown finishes. |
| `[CALIB FAIL] Chest gravity implausible` | Chest sensor tilted at an extreme angle (> 45°) or upside-down. | Make sure the sensor plate sits flat on the sternum, chip facing UP. |
| `[CALIB FAIL] Tilt/pre-pressure divergence` | Rescuer was already leaning hard on the chest before calibration finished. | Rest hands lightly without pushing down. |

---

## 5. Phase 3: The 15-Second Decoupled Manikin Calibration Protocol

Because CPR manikins (e.g., Laerdal Little Anne, Prestan) report **session mean depth** at the end of a trial, calibration is performed using this standardized **15-second comparative run**:

```
+---------------------------------------------------------------------------------+
|                   DECOUPLED 15-SECOND CALIBRATION WORKFLOW                      |
+---------------------------------------------------------------------------------+
| Step 1: Reference Manikin Run (No Vest or Mechanical Clicker Target)           |
| Perform steady compressions directly on the manikin to establish ground truth   |
| (e.g. D_manikin = 5.2 cm from the manikin app or 5.0 cm on mechanical clicker). |
|                                                                                 |
| Step 2: Zero Resting Baseline (Vest on Manikin Chest)                           |
| 1. Place the CPReady vest flat on the manikin's chest plate.                    |
| 2. Rest hands lightly on the chest handpiece.                                   |
| 3. Tap "Zero Baseline" in the app (sends SET_TIME:15 and CALIBRATE).            |
| 4. Hold hands completely still for 2.0 seconds until Type 3 Ready is received.  |
|                                                                                 |
| Step 3: 15-Second Guided Vest Trial Run                                         |
| 1. When the app displays "Baseline Calibrated! Position hands over sternum":    |
| 2. Tap "Begin 15s Trial" (sends START).                                         |
| 3. Compress steadily to the clicker depth for 15 seconds.                       |
| 4. Vest auto-finalizes at 15s, transmits Type 4 summary, and resets duration.   |
| 5. Read CPReady's reported Mean Depth (e.g. D_vest = 4.40 cm).                  |
|                                                                                 |
| Step 4: Proportional Calibration & Flash ACK                                    |
| 1. In the app dialog, enter D_manikin (e.g. 5.2 cm) and tap "Save Calibration".|
| 2. App sends: CALIBRATE_TARGET:5.2                                              |
| 3. Vest computes: K_new = K_current * (5.2 / 4.40) = 13.24                     |
| 4. Vest commits K_new to Flash NVS and notifies Type 3 ACK.                    |
| 5. App displays "SUCCESS! Calibration saved to vest flash memory".              |
+---------------------------------------------------------------------------------+
```

> [!TIP]
> **Automated 1-Step Calibration via BLE**:
> Immediately after completing the 15-second vest run, the mobile app sends:
> ```text
> CALIBRATE_TARGET:5.2
> ```
> The ESP32 calculates $K_{\text{new}} = K_{\text{current}} \times (5.2 / \bar{D}_{\text{vest}})$, commits it to Flash NVS, and immediately returns **Packet Type 3 (`PKT_TYPE_CALIB_SUCCESS`) as an ACK** so the mobile app can confirm successful flash persistence!

---

## 6. Phase 4: Non-Volatile Flash Persistence (NVS)

Any calibration performed through the app or BLE is saved directly into the ESP32's **Non-Volatile Storage (Flash Memory)** under the `"cpready"` partition:

* **Saved Across Power Off**: Turning off the vest or disconnecting the battery will **not** lose your calibration.
* **Boot Restoration Order**: At boot (`setup()`), the firmware restores the saved profile *before* restoring the depth scalar $K$. This ensures that user-calibrated $K$ values persist across reboots without being overwritten by profile defaults:
  ```text
  [NVS] Flash configuration loaded: Profile=MANIKIN_STANDARD | Depth K=13.24
  ```
* **Factory Reset**: Sending `RESET_CONFIG` wipes flash memory and restores the hardcoded defaults (`MANIKIN_STANDARD`, $K=11.2$).

---

## 7. Bench Testing vs. Manikin Dynamics: Why Slow Presses Cause "10 cm"

### The Physics Behind the 10 cm Reading
CPReady computes depth using the Harmonic Motion formula:
$$\text{Depth} = K \cdot a_{pp} \cdot T^2$$

- In **real CPR at 110 CPM**, strokes occur every $0.55\text{ s} \implies T^2 = \mathbf{0.30}$. Depth calculates accurately to ~5.0 cm.
- In a **slow hand press on a desk (e.g. 1 stroke every 1.5s)**, $T^2 = \mathbf{2.25}$ (**$7.5\times$ multiplier explosion**!). The math calculates 15–30 cm, hitting the safety clamp at **`10.0 cm`**.

### Built-in Hardening Protections:
1. **Period Clamping**: Period $T$ is bounded strictly between `0.38s` (158 CPM) and `0.85s` (70 CPM).
2. **Idle Pause Recovery**: If you pause > 1.5 seconds or perform the first stroke of a run, $T$ anchors to `0.55s` (~110 CPM). This prevents isolated bench taps from ever locking to 10.0 cm!
3. **Cadence Consistency Check**: If your rhythm is unsteady (variance > 25%), the firmware sets `CADENCE_FLAG_STEADY = 0` (Byte 11) and triggers audio cue 7: *"Maintain a steady rhythm"*.

---

## 8. Dual Profiles & Parameter Reference

CPReady supports two operating modes:
1. **`MANIKIN_STANDARD` (Default)**: Strict thresholds tuned for adult CPR springs.
2. **`BENCH_TEST`**: Relaxed thresholds for gentle hand/desk testing without a stiff spring.

### Live Runtime BLE Commands (No Reflashing Required!)

Send plain-text commands to the BLE Command Characteristic (`6e400003-b5a3-f393-e0a9-e50e24dcca9e`):

| BLE Command | What It Does | Stored in Flash? | Example Use Case |
| :--- | :--- | :---: | :--- |
| `CALIBRATE_TARGET:<cm>` | Auto-scales $K$ based on 15s trial mean depth, saves to NVS, and emits Type 3 ACK | **Yes** | `CALIBRATE_TARGET:5.2` after a 15s manikin run |
| `SET_K:<val>` | Sets depth scalar $K$ directly | **Yes** | `SET_K:12.5` |
| `SET_PROFILE:BENCH` | Switches to relaxed bench thresholds (`0.25g` start, `-0.18g` recoil, $K=9.5$) | **Yes** | Testing on a table without a manikin |
| `SET_PROFILE:MANIKIN` | Restores standard AHA manikin thresholds (`0.45g` start, `-0.35g` recoil, $K=11.2$) | **Yes** | Training trials on training manikin |
| `RESET_CONFIG` | Clears flash NVS and restores factory defaults | **Yes** | Resetting corrupted settings |
| `GET_CONFIG` | Prints active profile, $K$, thresholds, and duration to Serial | No | Diagnostics |
| `SET_TIME:<sec>` | Sets trial duration in seconds (auto-reverts to 120s on disconnect/end) | In RAM | `SET_TIME:15` for calibration run |
| `CALIBRATE` | Triggers stationary 2.0s baseline calibration | In RAM | Pre-session setup |
| `START` | Begins active practice session | In RAM | After calibration completes |
| `STOP` | Ends active session, resets duration to 120s & transmits final summary | In RAM | Early completion |

---

## 9. Parameter Master Reference Cheat Sheet

| Parameter Name | Line in Config | Manikin Default | Bench Default | Safe Range | When to Adjust |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `DEPTH_CALIBRATION_K` | 43 | `11.2f` | `9.5f` | `8.0f – 15.0f` | If 15s session mean depth reads too shallow or deep |
| `COMPRESSION_START_THRESHOLD_G` | 44 | `0.45f` | `0.25f` | `0.20f – 0.60f` | Lower for soft hand presses; raise to reject fidgets |
| `RECOIL_THRESHOLD_G` | 45 | `-0.35f`| `-0.18f`| `-0.15f – -0.50f`| Relax on bench (no spring); tighten on manikin |
| `CALIBRATION_RUN_DURATION_SEC` | 59 | `15 s` | `15 s` | `10 – 30 s` | Duration of the comparative calibration run |
| `MIN_CPR_PERIOD_SEC` | 53 | `0.38f` | `0.38f` | `0.30f – 0.45f` | Prevents hyper-rapid noise from calculating 0 depth |
| `MAX_CPR_PERIOD_SEC` | 54 | `0.85f` | `0.85f` | `0.70f – 1.00f` | Prevents slow strokes from calculating massive depth |
| `FALLBACK_CADENCE_PERIOD_SEC` | 55 | `0.55f` | `0.55f` | `0.50f – 0.60f` | Period used after pauses or on stroke #1 |
| `REFRACTORY_LOCKOUT_MS` | 95 | `250 ms`| `250 ms`| `180 – 300 ms` | Spring bounce causes double-counts |
| `LOWPASS_FILTER_ALPHA` | 94 | `0.25f` | `0.25f` | `0.18f – 0.35f` | Lower if numbers jitter; raise if depth lags |

---

## 10. Quick 5-Minute Lab Trial Checklist

- [ ] **1. Sensor Flatness**: Both MPU chips face UP; chest sensor flush on sternum; base sensor flat beneath the back.
- [ ] **2. Hardware Scan**: Power on ESP32; confirm PCA9548A multiplexer and both MPU sensors detected on SD3 and SD2.
- [ ] **3. Profile Selection**: Set to `MANIKIN_STANDARD` for manikin practice (or `BENCH_TEST` for desk experiments).
- [ ] **4. 15s Comparative Calibration**:
  - Rest hands on chest piece $\implies$ Tap "Zero Baseline" (keep still for 2.0s).
  - Tap "Begin 15s Trial" $\implies$ Compress steadily to the clicker for 15 seconds.
  - In dialog, enter manikin reported depth (e.g. `5.2 cm`) $\implies$ Tap "Save Calibration".
  - Confirm green success banner (Packet Type 3 ACK received and $K$ persisted to Flash NVS).
- [ ] **5. Resting Baseline**: Send `"CALIBRATE"`; confirm 2-second countdown with no error warnings.
- [ ] **6. Training Run**: Send `"START"`; deliver compressions at ~110 BPM. Confirm reported mean depth at trial completion matches the manikin clicker within $\pm 2$ to 3 mm.
