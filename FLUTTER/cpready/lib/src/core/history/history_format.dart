/// Display formatting for the History screen.
///
/// The patterns, month names, separators and am/pm suffixes are data and live in
/// [AppHistory]; only the substitution happens here.

import '../../config/config.dart';

/// Zero-pads [value] to two digits.
String _two(int value) => value.toString().padLeft(2, '0');

/// Renders a session timestamp using [AppHistory.datePattern] and
/// [AppHistory.timePattern], e.g. "Oct 19, 2026 2:32 PM".
String formatHistoryTimestamp(DateTime value) {
  final String date = AppHistory.datePattern
      .replaceAll('MMM', AppHistory.monthAbbreviations[value.month - 1])
      .replaceAll('yyyy', value.year.toString())
      .replaceAll('d', value.day.toString());

  final int hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final String time = AppHistory.timePattern
      .replaceAll('hh', _two(hour12))
      .replaceAll('h', hour12.toString())
      .replaceAll('mm', _two(value.minute))
      .replaceAll('A', value.hour < 12 ? AppHistory.amSuffix : AppHistory.pmSuffix);

  return '$date${AppHistory.dateTimeSeparator}$time';
}

/// Renders a session duration in clock style, e.g. "00:45", "02:05", "12:00".
///
/// Minutes are not wrapped at 60, so a 62-minute session reads "62:05".
String formatHistoryDuration(int seconds) {
  final int minutes = seconds ~/ 60;
  final int remainder = seconds % 60;
  return '${_two(minutes)}${AppHistory.durationSeparator}${_two(remainder)}';
}
