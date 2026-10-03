#ifndef BENCH_WEB_UI_H
#define BENCH_WEB_UI_H

#include <Arduino.h>

const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CPReady - Test Bench & Calibration Portal</title>
<style>
:root {
  --bg: #0f172a;
  --card: #1e293b;
  --card-border: #334155;
  --text: #f8fafc;
  --text-muted: #94a3b8;
  --accent: #38bdf8;
  --accent-glow: rgba(56, 189, 248, 0.25);
  --success: #22c55e;
  --success-glow: rgba(34, 197, 94, 0.25);
  --warning: #f59e0b;
  --danger: #ef4444;
  --danger-glow: rgba(239, 68, 68, 0.25);
}
* { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
body { background: var(--bg); color: var(--text); padding: 16px; min-height: 100vh; }
.container { max-width: 900px; margin: 0 auto; display: flex; flex-direction: column; gap: 16px; }

/* Header & Badges */
header { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 12px; background: var(--card); border: 1px solid var(--card-border); padding: 16px 20px; border-radius: 12px; }
.title-group h1 { font-size: 1.4rem; font-weight: 700; color: var(--text); display: flex; align-items: center; gap: 8px; }
.title-group p { font-size: 0.85rem; color: var(--text-muted); margin-top: 2px; }
.badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 20px; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; }
.badge-ok { background: rgba(34, 197, 94, 0.15); color: var(--success); border: 1px solid var(--success); }
.badge-warn { background: rgba(245, 158, 11, 0.15); color: var(--warning); border: 1px solid var(--warning); }
.badge-danger { background: rgba(239, 68, 68, 0.15); color: var(--danger); border: 1px solid var(--danger); }
.badge-info { background: rgba(56, 189, 248, 0.15); color: var(--accent); border: 1px solid var(--accent); }

/* Mode Switch Card */
.mode-card { background: var(--card); border: 1px solid var(--card-border); padding: 14px 20px; border-radius: 12px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; }
.mode-info h3 { font-size: 1rem; color: var(--accent); }
.mode-info p { font-size: 0.8rem; color: var(--text-muted); }
.toggle-btn { background: #334155; color: var(--text); border: none; padding: 8px 16px; border-radius: 8px; font-weight: 600; cursor: pointer; transition: all 0.2s; font-size: 0.85rem; }
.toggle-btn.active { background: var(--accent); color: #0f172a; }

/* Action Bar */
.action-card { background: var(--card); border: 1px solid var(--card-border); padding: 16px; border-radius: 12px; display: flex; flex-wrap: wrap; gap: 10px; align-items: center; justify-content: space-between; }
.btn { padding: 10px 18px; border-radius: 8px; font-weight: 600; border: none; cursor: pointer; transition: transform 0.1s, background 0.2s; font-size: 0.9rem; display: inline-flex; align-items: center; gap: 8px; }
.btn:active { transform: scale(0.97); }
.btn-primary { background: var(--accent); color: #0f172a; }
.btn-primary:hover { background: #7dd3fc; }
.btn-success { background: var(--success); color: #0f172a; }
.btn-danger { background: var(--danger); color: #fff; }
.btn-secondary { background: #334155; color: var(--text); }
.btn-secondary:hover { background: #475569; }

/* Telemetry Grid */
.telemetry-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 14px; }
.metric-card { background: var(--card); border: 1px solid var(--card-border); border-radius: 12px; padding: 18px; display: flex; flex-direction: column; justify-content: space-between; position: relative; overflow: hidden; }
.metric-card::before { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 4px; background: #334155; }
.metric-card.target-ok::before { background: var(--success); }
.metric-card.target-warn::before { background: var(--warning); }
.metric-card.target-danger::before { background: var(--danger); }
.metric-title { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); font-weight: 600; }
.metric-val { font-size: 2.2rem; font-weight: 800; margin: 8px 0; display: flex; align-items: baseline; gap: 6px; }
.metric-val .unit { font-size: 0.9rem; font-weight: 500; color: var(--text-muted); }
.metric-sub { font-size: 0.75rem; color: var(--text-muted); font-weight: 500; }

/* Status Banner */
.recoil-badge { display: inline-block; padding: 6px 12px; border-radius: 6px; font-weight: 700; font-size: 0.9rem; text-align: center; }
.recoil-ok { background: rgba(34, 197, 94, 0.2); color: var(--success); border: 1px solid var(--success); }
.recoil-lean { background: rgba(239, 68, 68, 0.2); color: var(--danger); border: 1px solid var(--danger); animation: pulse 1s infinite; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.6; } }

/* Tuning Section */
.tuning-section { background: var(--card); border: 1px solid var(--card-border); border-radius: 12px; padding: 20px; }
.tuning-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; border-bottom: 1px solid var(--card-border); padding-bottom: 12px; }
.tuning-header h2 { font-size: 1.1rem; color: var(--text); }
.setting-item { margin-bottom: 18px; padding-bottom: 14px; border-bottom: 1px solid rgba(255,255,255,0.05); }
.setting-item:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
.setting-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
.setting-label { font-size: 0.9rem; font-weight: 600; color: var(--text); }
.setting-value-badge { font-size: 0.85rem; font-weight: 700; color: var(--accent); background: #0f172a; padding: 2px 8px; border-radius: 4px; border: 1px solid #334155; }
.setting-desc { font-size: 0.75rem; color: var(--text-muted); line-height: 1.4; margin-bottom: 8px; }
.slider-group { display: flex; align-items: center; gap: 12px; }
input[type="range"] { flex: 1; accent-color: var(--accent); cursor: pointer; }
input[type="number"] { width: 85px; background: #0f172a; border: 1px solid var(--card-border); color: var(--text); padding: 6px 8px; border-radius: 6px; font-weight: 600; text-align: right; }

/* Code Export Modal/Box */
.export-box { background: #0b1120; border: 1px solid var(--card-border); border-radius: 8px; padding: 14px; font-family: monospace; font-size: 0.75rem; color: #38bdf8; white-space: pre-wrap; margin-top: 14px; max-height: 160px; overflow-y: auto; }
</style>
</head>
<body>

<div class="container">
  <!-- Header -->
  <header>
    <div class="title-group">
      <h1>CPReady Test Bench</h1>
      <p>AHA Metric Validation & Hardware Calibration Portal</p>
    </div>
    <div style="display:flex; gap:8px; align-items:center;">
      <span id="badgeChest" class="badge badge-warn">Chest: Checking...</span>
      <span id="badgeBase" class="badge badge-warn">Base: Checking...</span>
    </div>
  </header>

  <!-- Single vs Dual MPU Mode Selector -->
  <div class="mode-card">
    <div class="mode-info">
      <h3 id="modeTitle">Current: Single MPU Mode (Chest Only)</h3>
      <p id="modeDesc">Measuring sternal compression with resting gravity offset. Connect second sensor to enable surface decoupling.</p>
    </div>
    <button id="btnToggleMode" class="toggle-btn" onclick="toggleSensorMode()">Switch to Dual MPU</button>
  </div>

  <!-- Calibration and Control Bar -->
  <div class="action-card">
    <div style="display:flex; gap:10px; flex-wrap:wrap;">
      <button class="btn btn-primary" onclick="startCalibration()">
        <svg width="16" height="16" fill="currentColor" viewBox="0 0 16 16"><path d="M8 15A7 7 0 1 1 8 1a7 7 0 0 1 0 14zm0 1A8 8 0 1 0 8 0a8 8 0 0 0 0 16z"/><path d="M8 4a.5.5 0 0 1 .5.5v3h3a.5.5 0 0 1 0 1h-3v3a.5.5 0 0 1-1 0v-3h-3a.5.5 0 0 1 0-1h3v-3A.5.5 0 0 1 8 4z"/></svg>
        Calibrate Baseline (2s)
      </button>
      <button id="btnSession" class="btn btn-success" onclick="toggleSession()">Start Test Session</button>
      <button class="btn btn-secondary" onclick="resetSession()">Reset Stats</button>
    </div>
    <div style="font-size: 0.85rem; color: var(--text-muted);">
      Status: <strong id="calibStatus" style="color:var(--text);">Not Calibrated</strong>
    </div>
  </div>

  <!-- Real-Time AHA Telemetry Cards -->
  <div class="telemetry-grid">
    <!-- Rate -->
    <div id="cardRate" class="metric-card">
      <div class="metric-title">Compression Rate</div>
      <div class="metric-val"><span id="valRate">--</span> <span class="unit">cpm</span></div>
      <div class="metric-sub">AHA Target: <strong>100 – 120 cpm</strong></div>
    </div>

    <!-- Depth -->
    <div id="cardDepth" class="metric-card">
      <div class="metric-title">Compression Depth</div>
      <div class="metric-val"><span id="valDepth">--</span> <span class="unit">cm</span></div>
      <div class="metric-sub">AHA Target: <strong>5.0 – 6.0 cm</strong> (<span id="valDepthMm">--</span> mm)</div>
    </div>

    <!-- Recoil -->
    <div id="cardRecoil" class="metric-card">
      <div class="metric-title">Chest Recoil</div>
      <div style="margin: 12px 0;">
        <span id="badgeRecoil" class="recoil-badge recoil-ok">READY</span>
      </div>
      <div class="metric-sub">Session Recoil OK: <strong id="valRecoilPct">100%</strong></div>
    </div>

    <!-- CCF -->
    <div id="cardCCF" class="metric-card">
      <div class="metric-title">Compression Fraction (CCF)</div>
      <div class="metric-val"><span id="valCCF">--</span> <span class="unit">%</span></div>
      <div class="metric-sub">AHA Target: <strong>&ge; 60%</strong> (Active ratio)</div>
    </div>

    <!-- Stroke Count -->
    <div class="metric-card">
      <div class="metric-title">Total Compressions</div>
      <div class="metric-val"><span id="valStrokes">0</span> <span class="unit">strokes</span></div>
      <div class="metric-sub">Elapsed Time: <strong id="valElapsed">0s</strong></div>
    </div>

    <!-- Live Net Acceleration -->
    <div class="metric-card">
      <div class="metric-title">Net Vertical Accel (100Hz)</div>
      <div class="metric-val"><span id="valAccel">0.00</span> <span class="unit">g</span></div>
      <div class="metric-sub">Trigger Level: <strong id="valThreshSub">0.45 g</strong></div>
    </div>
  </div>

  <!-- Settings & Explanations Panel -->
  <div class="tuning-section">
    <div class="tuning-header">
      <h2>Parameter Calibration & Manikin Tuning</h2>
      <div style="display:flex; gap:8px;">
        <button class="btn btn-secondary" onclick="restoreDefaults()" style="font-size:0.75rem; padding:6px 12px;">Reset Defaults</button>
        <button class="btn btn-primary" onclick="saveSettings()" style="font-size:0.75rem; padding:6px 12px;">Save to Memory</button>
      </div>
    </div>

    <!-- 1. Depth Multiplier K -->
    <div class="setting-item">
      <div class="setting-top">
        <span class="setting-label">Depth Calibration Multiplier (K)</span>
        <span class="setting-value-badge" id="badgeDepthK">11.2</span>
      </div>
      <p class="setting-desc">
        <strong>What this does:</strong> Scales calculated harmonic compression depth into centimeters.<br>
        <strong>How to tune:</strong> Measure compression physically with a ruler on the manikin. If the physical ruler says <strong>5.0 cm</strong> but this portal shows <strong>4.0 cm</strong>, increase K: <code>New K = Current K * (Ruler / App)</code>.
      </p>
      <div class="slider-group">
        <input type="range" id="rngDepthK" min="5.0" max="25.0" step="0.1" value="11.2" oninput="syncSetting('DepthK', this.value)">
        <input type="number" id="numDepthK" min="5.0" max="25.0" step="0.1" value="11.2" onchange="syncSetting('DepthK', this.value)">
      </div>
    </div>

    <!-- 2. Compression Start Threshold -->
    <div class="setting-item">
      <div class="setting-top">
        <span class="setting-label">Downstroke Push Sensitivity (g)</span>
        <span class="setting-value-badge" id="badgeCThresh">0.45 g</span>
      </div>
      <p class="setting-desc">
        <strong>What this does:</strong> The minimum downward acceleration required to recognize a compression stroke.<br>
        <strong>How to tune:</strong> Lower this (e.g. 0.35g) if gentle pushes are not being detected. Raise this (e.g. 0.55g) if light table bumps trigger false strokes.
      </p>
      <div class="slider-group">
        <input type="range" id="rngCThresh" min="0.20" max="1.00" step="0.01" value="0.45" oninput="syncSetting('CThresh', this.value)">
        <input type="number" id="numCThresh" min="0.20" max="1.00" step="0.01" value="0.45" onchange="syncSetting('CThresh', this.value)">
      </div>
    </div>

    <!-- 3. Recoil Strictness Threshold -->
    <div class="setting-item">
      <div class="setting-top">
        <span class="setting-label">Recoil Rebound Threshold (g)</span>
        <span class="setting-value-badge" id="badgeRThresh">-0.35 g</span>
      </div>
      <p class="setting-desc">
        <strong>What this does:</strong> Verifies that the chest sprang back upward completely without the rescuer leaning on the chest.<br>
        <strong>How to tune:</strong> Making this number more negative (e.g. -0.45g) requires a stronger upward rebound snap. If trainees release completely but the portal still warns 'Leaning', make it closer to zero (e.g. -0.25g).
      </p>
      <div class="slider-group">
        <input type="range" id="rngRThresh" min="-0.80" max="-0.10" step="0.01" value="-0.35" oninput="syncSetting('RThresh', this.value)">
        <input type="number" id="numRThresh" min="-0.80" max="-0.10" step="0.01" value="-0.35" onchange="syncSetting('RThresh', this.value)">
      </div>
    </div>

    <!-- 4. Refractory Lockout -->
    <div class="setting-item">
      <div class="setting-top">
        <span class="setting-label">Stroke Refractory Lockout (ms)</span>
        <span class="setting-value-badge" id="badgeRefr">250 ms</span>
      </div>
      <p class="setting-desc">
        <strong>What this does:</strong> The minimum pause between strokes to reject mechanical foam bounce. A 250 ms lockout safely caps the maximum detectable rate at 240 cpm, preventing a single stroke from being counted twice.
      </p>
      <div class="slider-group">
        <input type="range" id="rngRefr" min="150" max="400" step="10" value="250" oninput="syncSetting('Refr', this.value)">
        <input type="number" id="numRefr" min="150" max="400" step="10" value="250" onchange="syncSetting('Refr', this.value)">
      </div>
    </div>

    <!-- Research Paper Config Exporter -->
    <div style="margin-top: 18px;">
      <button class="btn btn-secondary" onclick="generateConfigCode()" style="width: 100%;">
        📋 Generate C++ Configuration Block for Research Paper / Final Firmware
      </button>
      <div id="exportBox" class="export-box" style="display:none;"></div>
    </div>
  </div>
</div>

<script>
let currentConfig = {
  depthK: 11.2,
  compressionThreshG: 0.45,
  recoilThreshG: -0.35,
  refractoryMs: 250,
  useDualMpu: false
};
let isSessionActive = false;

function syncSetting(name, val) {
  val = parseFloat(val);
  if (name === 'DepthK') {
    currentConfig.depthK = val;
    document.getElementById('rngDepthK').value = val;
    document.getElementById('numDepthK').value = val;
    document.getElementById('badgeDepthK').innerText = val.toFixed(1);
  } else if (name === 'CThresh') {
    currentConfig.compressionThreshG = val;
    document.getElementById('rngCThresh').value = val;
    document.getElementById('numCThresh').value = val;
    document.getElementById('badgeCThresh').innerText = val.toFixed(2) + ' g';
    document.getElementById('valThreshSub').innerText = val.toFixed(2) + ' g';
  } else if (name === 'RThresh') {
    currentConfig.recoilThreshG = val;
    document.getElementById('rngRThresh').value = val;
    document.getElementById('numRThresh').value = val;
    document.getElementById('badgeRThresh').innerText = val.toFixed(2) + ' g';
  } else if (name === 'Refr') {
    currentConfig.refractoryMs = parseInt(val);
    document.getElementById('rngRefr').value = val;
    document.getElementById('numRefr').value = val;
    document.getElementById('badgeRefr').innerText = val + ' ms';
  }
}

async function fetchMetrics() {
  try {
    const res = await fetch('/api/metrics');
    if (!res.ok) return;
    const d = await res.json();

    // Rate
    const rateEl = document.getElementById('valRate');
    const cardRate = document.getElementById('cardRate');
    if (d.rate > 0) {
      rateEl.innerText = Math.round(d.rate);
      cardRate.className = 'metric-card ' + (d.rate >= 100 && d.rate <= 120 ? 'target-ok' : (d.rate < 100 ? 'target-warn' : 'target-danger'));
    } else {
      rateEl.innerText = '--';
      cardRate.className = 'metric-card';
    }

    // Depth
    const depthEl = document.getElementById('valDepth');
    const depthMmEl = document.getElementById('valDepthMm');
    const cardDepth = document.getElementById('cardDepth');
    if (d.depth > 0) {
      depthEl.innerText = d.depth.toFixed(1);
      depthMmEl.innerText = Math.round(d.depth * 10);
      cardDepth.className = 'metric-card ' + (d.depth >= 5.0 && d.depth <= 6.0 ? 'target-ok' : (d.depth < 5.0 ? 'target-warn' : 'target-danger'));
    } else {
      depthEl.innerText = '--';
      depthMmEl.innerText = '--';
      cardDepth.className = 'metric-card';
    }

    // Recoil
    const badgeRecoil = document.getElementById('badgeRecoil');
    if (d.strokes > 0) {
      if (d.recoil_ok) {
        badgeRecoil.className = 'recoil-badge recoil-ok';
        badgeRecoil.innerText = 'FULL RELEASE (Good)';
      } else {
        badgeRecoil.className = 'recoil-badge recoil-lean';
        badgeRecoil.innerText = 'LEANING / INCOMPLETE';
      }
    } else {
      badgeRecoil.className = 'recoil-badge recoil-ok';
      badgeRecoil.innerText = 'READY';
    }
    document.getElementById('valRecoilPct').innerText = Math.round(d.recoil_pct) + '%';

    // CCF
    const ccfEl = document.getElementById('valCCF');
    const cardCCF = document.getElementById('cardCCF');
    if (d.elapsed > 0) {
      ccfEl.innerText = Math.round(d.ccf);
      cardCCF.className = 'metric-card ' + (d.ccf >= 60 ? 'target-ok' : 'target-warn');
    } else {
      ccfEl.innerText = '--';
      cardCCF.className = 'metric-card';
    }

    // Strokes & Time
    document.getElementById('valStrokes').innerText = d.strokes;
    document.getElementById('valElapsed').innerText = d.elapsed + 's';
    document.getElementById('valAccel').innerText = (d.accel >= 0 ? '+' : '') + d.accel.toFixed(2);

    // Hardware Badges
    const bChest = document.getElementById('badgeChest');
    bChest.className = 'badge ' + (d.chest_ok ? 'badge-ok' : 'badge-danger');
    bChest.innerText = d.chest_ok ? 'Chest: 0x68 OK' : 'Chest: 0x68 MISSING';

    const bBase = document.getElementById('badgeBase');
    bBase.className = 'badge ' + (d.base_ok ? 'badge-ok' : 'badge-warn');
    bBase.innerText = d.base_ok ? 'Base: 0x69 DETECTED' : 'Base: OFFLINE';

    // Calib Status
    const calibEl = document.getElementById('calibStatus');
    if (d.is_calibrating) {
      calibEl.innerText = 'Calibrating baseline... Keep hands still!';
      calibEl.style.color = 'var(--warning)';
    } else if (d.is_calibrated) {
      calibEl.innerText = 'Calibrated & Ready';
      calibEl.style.color = 'var(--success)';
    }

    // Session Button state sync
    isSessionActive = d.session_active;
    const btnS = document.getElementById('btnSession');
    if (isSessionActive) {
      btnS.className = 'btn btn-danger';
      btnS.innerText = 'Stop Test Session';
    } else {
      btnS.className = 'btn btn-success';
      btnS.innerText = 'Start Test Session';
    }

  } catch (err) {
    console.error('Fetch error:', err);
  }
}

async function loadConfig() {
  try {
    const res = await fetch('/api/config');
    if (!res.ok) return;
    const c = await res.json();
    currentConfig = c;
    syncSetting('DepthK', c.depthK);
    syncSetting('CThresh', c.compressionThreshG);
    syncSetting('RThresh', c.recoilThreshG);
    syncSetting('Refr', c.refractoryMs);
    updateModeDisplay(c.useDualMpu);
  } catch (err) {
    console.error('Config fetch error:', err);
  }
}

function updateModeDisplay(isDual) {
  currentConfig.useDualMpu = isDual;
  const title = document.getElementById('modeTitle');
  const desc = document.getElementById('modeDesc');
  const btn = document.getElementById('btnToggleMode');

  if (isDual) {
    title.innerText = 'Current: Dual MPU Mode (Differential Decoupling)';
    title.style.color = 'var(--success)';
    desc.innerText = 'Subtracting spine reference (0x69) from chest (0x68) to isolate sternal compression from foam/mattress bounce.';
    btn.innerText = 'Switch to Single MPU';
    btn.className = 'toggle-btn active';
  } else {
    title.innerText = 'Current: Single MPU Mode (Chest Only)';
    title.style.color = 'var(--accent)';
    desc.innerText = 'Measuring sternal compression with resting gravity offset. Connect second sensor to enable surface decoupling.';
    btn.innerText = 'Switch to Dual MPU';
    btn.className = 'toggle-btn';
  }
}

async function toggleSensorMode() {
  const newMode = !currentConfig.useDualMpu;
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'set_mode', dual: newMode })
  });
  updateModeDisplay(newMode);
}

async function startCalibration() {
  document.getElementById('calibStatus').innerText = 'Calibrating (Keep Still)...';
  document.getElementById('calibStatus').style.color = 'var(--warning)';
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'calibrate' })
  });
}

async function toggleSession() {
  const act = isSessionActive ? 'stop_session' : 'start_session';
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: act })
  });
}

async function resetSession() {
  await fetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'reset_session' })
  });
}

async function saveSettings() {
  const res = await fetch('/api/config', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(currentConfig)
  });
  if (res.ok) {
    alert('Settings successfully saved to ESP32 Flash memory! They will persist across reboots.');
  } else {
    alert('Failed to save settings.');
  }
}

async function restoreDefaults() {
  if (confirm('Reset all parameters back to factory defaults?')) {
    await fetch('/api/action', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'restore_defaults' })
    });
    await loadConfig();
  }
}

function generateConfigCode() {
  const box = document.getElementById('exportBox');
  const code = 
`// ==============================================================================
// CPReady Calibrated Parameters (Exported from Test Bench)
// ==============================================================================
#define DEPTH_CALIBRATION_K    ${currentConfig.depthK.toFixed(2)}f   // Tested depth scalar
#define COMPRESSION_THRESH_G   ${currentConfig.compressionThreshG.toFixed(2)}f   // Tested downstroke sensitivity
#define RECOIL_THRESH_G        ${currentConfig.recoilThreshG.toFixed(2)}f  // Tested rebound strictness
#define REFRACTORY_LOCKOUT_MS  ${currentConfig.refractoryMs}      // Debounce window (ms)
#define SENSOR_MODE_DUAL       ${currentConfig.useDualMpu ? 'true' : 'false'}   // Dual-MPU differential enabled
// Paste this directly into CPReadyConfig.h or your Capstone Methodology!`;

  box.innerText = code;
  box.style.display = 'block';
}

window.onload = () => {
  loadConfig();
  setInterval(fetchMetrics, 100); // 10 Hz refresh
};
</script>

</body>
</html>
)rawliteral";

#endif // BENCH_WEB_UI_H
