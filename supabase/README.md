# CPReady raw telemetry upload

The app records raw chest/base accelerometer samples locally first, then uploads
the session folder to Supabase when the generated build includes a project URL
and publishable key.

## 1. Create the Supabase resources

In the Supabase SQL editor, run:

```text
supabase/telemetry_schema.sql
```

That creates the private `recordings` bucket and the `telemetry_sessions` table
with insert-only policies for the `anon` role. It deliberately creates no
SELECT/UPDATE/DELETE policy for the app.

## 2. Build with the publishable key

Use the project URL and the **publishable/anon** key. Never use the service-role
key in the app.

```bash
cd FLUTTER/cpready
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Without those defines the app still records locally and shows "Saved locally —
Supabase upload is not configured". After installing a build with credentials,
the pending queue is retried on launch.

## 3. Where the files go

Each recording is one folder keyed by the session UUID:

```text
recordings/<session_uuid>/raw.csv
recordings/<session_uuid>/packets.csv
recordings/<session_uuid>/events.csv
recordings/<session_uuid>/session.json
```

Rows in `telemetry_sessions` carry the same UUID, participant code, counts,
missing-sample/frame counts, device provenance and `storage_prefix`.

## Local files

On the phone, the same four files live under the app documents directory:

```text
recordings/<session_uuid>/
```

`session.json` is written at start with status `recording` and rewritten
atomically at stop. If the app is killed mid-session, the row is marked
`incomplete` on the next launch and is not auto-uploaded; the CSVs remain
available for manual recovery.
