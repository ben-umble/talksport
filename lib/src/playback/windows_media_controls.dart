import 'dart:async';
import 'dart:io';

import 'package:smtc_windows/smtc_windows.dart' as smtc;

import '../models/playback_item.dart';
import 'media_controls_bridge.dart';

class WindowsMediaControls implements MediaControlsBridge {
  WindowsMediaControls._(this._smtc);

  static Future<WindowsMediaControls?> create() async {
    if (!Platform.isWindows) {
      return null;
    }
    await smtc.SMTCWindows.initialize();
    return WindowsMediaControls._(
      smtc.SMTCWindows(
        enabled: true,
        config: const smtc.SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          stopEnabled: true,
          nextEnabled: false,
          prevEnabled: false,
          fastForwardEnabled: true,
          rewindEnabled: true,
        ),
      ),
    );
  }

  final smtc.SMTCWindows _smtc;
  StreamSubscription<smtc.PressedButton>? _buttonSubscription;

  @override
  void bind({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function() onRewind,
    required Future<void> Function() onFastForward,
  }) {
    _buttonSubscription?.cancel();
    _buttonSubscription = _smtc.buttonPressStream.listen((button) {
      switch (button) {
        case smtc.PressedButton.play:
          unawaited(onPlay());
        case smtc.PressedButton.pause:
          unawaited(onPause());
        case smtc.PressedButton.stop:
          unawaited(onStop());
        case smtc.PressedButton.previous:
        case smtc.PressedButton.rewind:
          unawaited(onRewind());
        case smtc.PressedButton.next:
        case smtc.PressedButton.fastForward:
          unawaited(onFastForward());
        case smtc.PressedButton.record:
        case smtc.PressedButton.channelUp:
        case smtc.PressedButton.channelDown:
          break;
      }
    });
  }

  @override
  Future<void> updateItem(PlaybackItem item) async {
    await _smtc.updateMetadata(
      smtc.MusicMetadata(
        title: item.title,
        artist: item.subtitle,
        album: item.stationName,
        albumArtist: item.stationName,
        thumbnail: item.imageUrl,
      ),
    );
    await _smtc.updateConfig(
      smtc.SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        stopEnabled: true,
        nextEnabled: false,
        prevEnabled: false,
        fastForwardEnabled: item.isCatchUp,
        rewindEnabled: item.isCatchUp,
      ),
    );
  }

  @override
  Future<void> updatePlaybackStatus({required bool playing}) {
    return _smtc.setPlaybackStatus(
      playing ? smtc.PlaybackStatus.playing : smtc.PlaybackStatus.paused,
    );
  }

  @override
  Future<void> updateTimeline({
    required Duration position,
    Duration? duration,
    required bool seekable,
  }) {
    final end = duration ?? Duration.zero;
    return _smtc.updateTimeline(
      smtc.PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: end.inMilliseconds,
        positionMs: position.inMilliseconds,
        minSeekTimeMs: seekable ? 0 : null,
        maxSeekTimeMs: seekable ? end.inMilliseconds : null,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _buttonSubscription?.cancel();
    await _smtc.dispose();
  }
}
