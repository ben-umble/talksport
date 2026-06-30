import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/progress_store.dart';
import '../models/playback_item.dart';
import '../util/playback_math.dart';
import 'media_controls_bridge.dart';
import 'playback_controller.dart';

class TalkSportAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements PlaybackController {
  TalkSportAudioHandler(
    this._progressStore,
    MediaControlsBridge? mediaControls, {
    bool configureSession = true,
  }) : _mediaControls = mediaControls {
    if (configureSession) {
      _configureAudioSession();
    }
    _bindMediaControls();
    _playbackSubscription = _player.playbackEventStream.listen(
      _broadcastPlaybackState,
      onError: (Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorMessage: error.toString(),
          ),
        );
      },
    );
    _durationSubscription = _player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current != null && duration != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
    _positionSubscription = _player.positionStream.listen(_onPositionChanged);
  }

  final ProgressStore _progressStore;
  MediaControlsBridge? _mediaControls;
  final AudioPlayer _player = AudioPlayer();
  @override
  final ValueNotifier<PlaybackItem?> currentItem = ValueNotifier(null);
  late final StreamSubscription<PlaybackEvent> _playbackSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loadingItem = false;

  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

  @override
  PlaybackState get playbackStateValue => playbackState.value;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  bool get isPlaying => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration ?? currentItem.value?.duration;

  @override
  Future<void> playItem(PlaybackItem item) async {
    await _loadItem(item, playWhenReady: true);
  }

  Future<void> restoreLastItem() async {
    final last = _progressStore.lastItem();
    if (last == null || !last.isCatchUp) {
      return;
    }
    await _loadItem(last, playWhenReady: false);
  }

  Future<void> _loadItem(
    PlaybackItem item, {
    required bool playWhenReady,
  }) async {
    if (item.audioUrl.isEmpty) {
      throw StateError('No audio URL is available for ${item.title}.');
    }
    _loadingItem = true;
    try {
      currentItem.value = item;
      final media = item.toMediaItem();
      mediaItem.add(media);
      await _mediaControls?.updateItem(item);
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(item.audioUrl), tag: media),
      );
      final saved = item.isCatchUp ? _progressStore.progressFor(item.id) : null;
      final resume = saved?.position ?? Duration.zero;
      final knownDuration = item.duration ?? _player.duration;
      if (resume > Duration.zero &&
          (knownDuration == null || resume < knownDuration)) {
        await _player.seek(resume);
      }
      await _progressStore.saveLastItem(item);
    } finally {
      _loadingItem = false;
    }
    if (playWhenReady) {
      await play();
    } else {
      await _mediaControls?.updatePlaybackStatus(playing: false);
    }
  }

  @override
  Future<void> replayLastItem() async {
    final last = _progressStore.lastItem();
    if (last != null) {
      await playItem(last);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _saveProgress(force: true);
    await _player.stop();
    currentItem.value = null;
    await _mediaControls?.updatePlaybackStatus(playing: false);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final item = currentItem.value;
    if (item?.isLive ?? true) {
      return;
    }
    await _player.seek(position);
    await _saveProgress(force: true);
  }

  @override
  Future<void> fastForward() async {
    final item = currentItem.value;
    if (item == null || item.isLive) {
      return;
    }
    await seek(
      clampSeekPosition(
        current: _player.position,
        delta: const Duration(seconds: 15),
        duration: duration,
      ),
    );
  }

  @override
  Future<void> rewind() async {
    final item = currentItem.value;
    if (item == null || item.isLive) {
      return;
    }
    await seek(
      clampSeekPosition(
        current: _player.position,
        delta: const Duration(seconds: -15),
        duration: duration,
      ),
    );
  }

  Future<void> dispose() async {
    await _saveProgress(force: true);
    await _playbackSubscription.cancel();
    await _durationSubscription.cancel();
    await _positionSubscription.cancel();
    await _player.dispose();
    await _mediaControls?.dispose();
    currentItem.dispose();
  }

  Future<void> flushProgress() => _saveProgress(force: true);

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> attachMediaControls(MediaControlsBridge mediaControls) async {
    await _mediaControls?.dispose();
    _mediaControls = mediaControls;
    _bindMediaControls();
    final item = currentItem.value;
    if (item != null) {
      await mediaControls.updateItem(item);
      await mediaControls.updatePlaybackStatus(playing: _player.playing);
      await mediaControls.updateTimeline(
        position: _player.position,
        duration: duration,
        seekable: item.isCatchUp,
      );
    }
  }

  void _bindMediaControls() {
    _mediaControls?.bind(
      onPlay: play,
      onPause: pause,
      onStop: stop,
      onRewind: rewind,
      onFastForward: fastForward,
    );
  }

  void _broadcastPlaybackState(PlaybackEvent event) {
    final item = currentItem.value;
    final isCatchUp = item?.isCatchUp ?? false;
    final controls = <MediaControl>[
      if (isCatchUp) MediaControl.rewind,
      if (_player.playing) MediaControl.pause else MediaControl.play,
      if (isCatchUp) MediaControl.fastForward,
      MediaControl.stop,
    ];
    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: {
          if (isCatchUp) MediaAction.seek,
          if (isCatchUp) MediaAction.seekBackward,
          if (isCatchUp) MediaAction.seekForward,
        },
        androidCompactActionIndices: isCatchUp ? const [0, 1, 2] : const [0, 1],
        processingState: _mapProcessingState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: event.bufferedPosition,
        speed: _player.speed,
      ),
    );
    unawaited(_mediaControls?.updatePlaybackStatus(playing: _player.playing));
  }

  void _onPositionChanged(Duration position) {
    final item = currentItem.value;
    unawaited(
      _mediaControls?.updateTimeline(
        position: position,
        duration: duration,
        seekable: item?.isCatchUp ?? false,
      ),
    );
    unawaited(_saveProgress());
  }

  Future<void> _saveProgress({bool force = false}) async {
    final item = currentItem.value;
    if (_loadingItem || item == null || item.isLive) {
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastProgressSave).inSeconds < 5) {
      return;
    }
    _lastProgressSave = now;
    await _progressStore.saveProgress(item, _player.position);
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }
}
