-- CPReady raw telemetry upload schema.
--
-- Run this once in the Supabase SQL editor. It creates:
--   * the private `recordings` storage bucket,
--   * the `telemetry_sessions` metadata table,
--   * insert-only policies for the app's publishable/anon key.
--
-- The app never needs SELECT/UPDATE/DELETE: uploads are idempotent by session
-- UUID, and 409 responses (object/row already exists) count as success.

-- ---------------------------------------------------------------------------
-- Storage bucket
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('recordings', 'recordings', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Metadata table
-- ---------------------------------------------------------------------------

create table if not exists public.telemetry_sessions (
  id               uuid primary key,
  participant_code text not null,
  experiment       text,
  notes            text,
  status           text not null,
  started_at       timestamptz not null,
  ended_at         timestamptz,
  sample_count     integer not null default 0,
  frame_count      integer not null default 0,
  missing_samples  integer not null default 0,
  missing_frames   integer not null default 0,
  size_bytes       bigint  not null default 0,
  device_name      text,
  device_id        text,
  app_version      text,
  storage_prefix   text not null,
  schema_version   integer not null default 1,
  created_at       timestamptz not null default now()
);

create index if not exists telemetry_sessions_started_at_idx
  on public.telemetry_sessions (started_at desc);

create index if not exists telemetry_sessions_participant_idx
  on public.telemetry_sessions (participant_code, started_at desc);

-- ---------------------------------------------------------------------------
-- Insert-only row policy
-- ---------------------------------------------------------------------------

alter table public.telemetry_sessions enable row level security;

drop policy if exists "anon insert telemetry sessions"
  on public.telemetry_sessions;

create policy "anon insert telemetry sessions"
  on public.telemetry_sessions
  for insert
  to anon
  with check (
    char_length(participant_code) between 1 and 64
    and char_length(storage_prefix) between 1 and 128
  );

-- No SELECT/UPDATE/DELETE policy for anon. Read the rows with the dashboard or
-- a service-role key on a trusted machine.

grant insert on public.telemetry_sessions to anon;

-- ---------------------------------------------------------------------------
-- Insert-only storage policy
-- ---------------------------------------------------------------------------

drop policy if exists "anon upload recordings" on storage.objects;

create policy "anon upload recordings"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'recordings');
