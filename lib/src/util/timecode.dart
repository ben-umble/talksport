Duration? parseTimecode(String value, {Duration? max}) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) {
    return null;
  }
  final parts = cleaned.split(':');
  if (parts.length > 3 || parts.any((part) => part.isEmpty)) {
    return null;
  }
  final numbers = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0) {
      return null;
    }
    numbers.add(number);
  }

  final seconds = switch (numbers.length) {
    1 => numbers[0],
    2 => numbers[0] * 60 + numbers[1],
    3 => numbers[0] * 3600 + numbers[1] * 60 + numbers[2],
    _ => 0,
  };
  final duration = Duration(seconds: seconds);
  if (max != null && duration > max) {
    return max;
  }
  return duration;
}

String formatDuration(Duration? duration) {
  if (duration == null) {
    return '--:--';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
