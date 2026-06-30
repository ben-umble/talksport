Duration clampSeekPosition({
  required Duration current,
  required Duration delta,
  Duration? duration,
}) {
  final target = current + delta;
  if (target.isNegative) {
    return Duration.zero;
  }
  if (duration != null && target > duration) {
    return duration;
  }
  return target;
}
