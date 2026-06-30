import '../models/playback_item.dart';

abstract interface class MediaControlsBridge {
  void bind({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function() onRewind,
    required Future<void> Function() onFastForward,
  });

  Future<void> updateItem(PlaybackItem item);

  Future<void> updatePlaybackStatus({required bool playing});

  Future<void> updateTimeline({
    required Duration position,
    Duration? duration,
    required bool seekable,
  });

  Future<void> dispose();
}
