# DATA Directory — Organized Session Trials & Ground-Truth Mapping

Each session `.zip` archive in `DATA/` has been extracted into `DATA/organized_trials/<index>_<mode>_<preset>_<short_id>/` along with:
- `raw.csv` — 100 Hz raw 3-axis accelerometer stream (`chest` and `base` MPUs in `mg`)
- `packets.csv` — BLE telemetry notifications recorded during the trial
- `events.csv` — Session lifecycle and command events
- `session.json` — Original session metadata (`started_at`, `ended_at`, `session_id`)
- `ground_truth.json` — Extracted Laerdal Little Anne QC ground-truth metrics and timestamp alignment
- `ground_truth_screenshot.jpg` — Copy of the paired Laerdal QC app screenshot (when available)

See [`../GROUND_TRUTH_ANALYSIS.md`](../GROUND_TRUTH_ANALYSIS.md) for the full kinematic analysis and parameter optimization results.

## Trial Index

| Folder | Session ID | Ended (`UTC+8` PHT) | Paired Screenshot | Mode & Preset | GT Compressions | GT Mean Depth | GT Avg Rate | GT Good Depth % | GT Release % |
| :--- | :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `01_2MPU_Balanced1_a4dc7413` | `a4dc7413-ebbd-44fd-82eb-7259d7c0c236` | `2026-11-03 15:36:00` | `Double MPU/2MPU_Balanced1.jpg` | `2-MPU` `BALANCED` | 52 | 46 mm | 103 /min | 37% | 100% |
| `02_2MPU_Balanced2_e5e68774` | `e5e68774-091f-4484-b17b-082e4774e95f` | `2026-11-03 15:38:34` | `Double MPU/2MPU_Balanced2.jpg` | `2-MPU` `BALANCED` | *(Score 21, 00:59)* | *(Below fold)* | *(Below fold)* | *(Below fold)* | *(Below fold)* |
| `03_2MPU_Interrupted_f71deb5f` | `f71deb5f-ebbb-47be-ad35-dd978b836c13` | `2026-11-03 15:39:42` | *(None — 2.6 s aborted run)* | `2-MPU` `BALANCED` | — | — | — | — | — |
| `04_2MPU_Strict1_7c5ea2c3` | `7c5ea2c3-d194-41d0-ae83-5aa20eb878b9` | `2026-11-04 13:50:26` | `Double MPU/2MPU_Strict1.jpg` | `2-MPU` `STRICT` | 103 | 54 mm | 104 /min | 77% | 99% |
| `05_2MPU_Strict2_f501e7c8` | `f501e7c8-f5fd-4a28-a38a-debd3a88a871` | `2026-11-04 13:52:47` | `Double MPU/2MPU_Strict2.jpg` | `2-MPU` `STRICT` | 69 | 57 mm | 109 /min | 97% | 100% |
| `06_2MPU_High1_343540cf` | `343540cf-11c4-4205-8d24-ed942d7ce644` | `2026-11-04 13:55:41` | `Double MPU/2MPU_High1.jpg` | `2-MPU` `HIGH` | 82 | 60 mm | 105 /min | 99% | 100% |
| `07_2MPU_High2_e5c4ad3a` | `e5c4ad3a-a7a0-4a9c-bcda-b14db62db4af` | `2026-11-04 13:58:30` | `Double MPU/2MPU_High2.jpg` | `2-MPU` `HIGH` | 69 | 59 mm | 101 /min | 99% | 100% |
| `08_1MPU_Strict1_6ee8938f` | `6ee8938f-1c06-48ac-aa91-3e3ac56fa048` | `2026-11-04 14:03:52` | `Single MPU/1MPU_Strict1.jpg` | `1-MPU` `STRICT` | 71 | 54 mm | 107 /min | 80% | 99% |
| `09_1MPU_Strict2_848e796c` | `848e796c-7db7-44aa-b4af-c73e154c772e` | `2026-11-04 14:06:44` | `Single MPU/1MPU_Strict2.jpg` | `1-MPU` `STRICT` | 71 | 57 mm | 103 /min | 97% | 99% |
| `10_1MPU_Balanced1_48011a51` | `48011a51-67f0-4a94-ae3c-b410e7366473` | `2026-11-04 14:10:06` | `Single MPU/1MPU_Balanced1.jpg` | `1-MPU` `BALANCED` | 70 | 58 mm | 102 /min | 100% | 100% |
| `11_1MPU_High2_44c2e739` | `44c2e739-01ee-483e-bac1-52c0137f5281` | `2026-11-04 14:18:14` | `Single MPU/1MPU_High2.jpg` | `1-MPU` `HIGH` | 80 | 51 mm | 102 /min | 59% | 100% |
