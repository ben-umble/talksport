import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/playback_item.dart';

abstract interface class PlaybackController {
  ValueListenable<PlaybackItem?> get currentItem;
  Stream<PlaybackState> get playbackStateStream;
  PlaybackState get playbackStateValue;
  Stream<Duration> get positionStream;
  Duration get position;
  Duration? get duration;

  Future<void> playItem(PlaybackItem item);
  Future<void> replayLastItem();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> fastForward();
  Future<void> rewind();
}
