/// Raw telemetry contract and local-recording configuration.
///
/// The byte layout mirrors `CPReady_Program/include/TelemetryFrames.h`. The
/// Supabase values are build-time defines so no secret is committed:
///
///   flutter run --dart-define=SUPABASE_URL=https://... \
///               --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// Only the publishable/anon key belongs in the app. The service-role key must
/// never be shipped to a device.
class AppTelemetry {
  // -----------------------------------------------------------------------
  // GATT
  // -----------------------------------------------------------------------

  /// Optional raw accelerometer characteristic (firmware `6e400004-...`).
  static const String characteristicUuid =
      '6e400004-b5a3-f393-e0a9-e50e24dcca9e';

  /// Opt-in commands for the raw stream.
  static const String commandOn = 'TELEM:1';
  static const String commandOff = 'TELEM:0';

  /// ATT MTU requested before service discovery. 247 leaves 244 bytes of
  /// notification payload, enough for a 176-byte 10-sample frame.
  static const int targetMtu = 247;

  // -----------------------------------------------------------------------
  // Frame contract (TelemetryFrames.h)
  // -----------------------------------------------------------------------

  static const int frameType = 0x10;
  static const int frameVersion = 1;
  static const int headerBytes = 16;
  static const int sampleBytes = 16;
  static const int maxSamplesPerFrame = 10;

  static const int flagStreaming = 0x01;
  static const int flagSensorFault = 0x02;
  static const int flagOverrun = 0x04;
  static const int flagCalibrating = 0x08;

  // -----------------------------------------------------------------------
  // Local recording layout
  // -----------------------------------------------------------------------

  /// Folder under the app documents directory; one child folder per session.
  static const String recordingsDirectory = 'recordings';

  static const String rawFileName = 'raw.csv';
  static const String metricsFileName = 'packets.csv';
  static const String eventsFileName = 'events.csv';
  static const String metadataFileName = 'session.json';

  /// Bump when a CSV column or the session.json shape changes.
  static const int schemaVersion = 2;

  static const String rawHeader =
      't_us,sample_index,frame_sequence,stroke_count,device_state,flags,'
      'chest_x_mg,chest_y_mg,chest_z_mg,base_x_mg,base_y_mg,base_z_mg,'
      'unclamped_depth_mm';

  static const String metricsHeader =
      'received_at,packet_type,recoil_status,rate_cpm,depth_tenths_mm,ccf_percent,'
      'audio_prompt_code,total_compressions,elapsed_sec,quality_flags,sequence';

  static const String eventsHeader = 'received_at,event,detail';

  // -----------------------------------------------------------------------
  // Supabase upload (publishable key only)
  // -----------------------------------------------------------------------

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static const String bucket = 'recordings';
  static const String table = 'telemetry_sessions';

  /// Every request gets this timeout; the queue retries later.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Upload is skipped (and left pending) until both values are supplied.
  static bool get isUploadConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
}
