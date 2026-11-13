
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  const sampleRate = 44100;
  const duration = 0.10;
  final count = (sampleRate * duration).round();

  final bytes = ByteData(44 + count * 2);

  void writeText(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  writeText(0, 'RIFF');
  bytes.setUint32(4, 36 + count * 2, Endian.little);
  writeText(8, 'WAVE');
  writeText(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeText(36, 'data');
  bytes.setUint32(40, count * 2, Endian.little);

  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    final envelope = exp(-55 * t);
    final wave = sin(2 * pi * 1200 * t);
    final sample = (wave * envelope * 28000).round();

    bytes.setInt16(44 + i * 2, sample, Endian.little);
  }

  final file = File('assets/audio/metronome_tick.wav');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes.buffer.asUint8List());

  print('Created: ${file.path}');
}
