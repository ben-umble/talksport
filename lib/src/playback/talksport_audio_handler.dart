import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/progress_store.dart';
import '../models/playback_item.dart';
import '../util/playback_math.dart';
import 'catch_up_download_cache.dart';
import 'media_controls_bridge.dart';
import 'playback_controller.dart';

class TalkSportAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements PlaybackController {
  TalkSportAudioHandler(
    this._progressStore,
    MediaControlsBridge? mediaControls, {
    this.refreshItem,
    this.downloadCache,
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
        unawaited(_recoverPlayback('player error: $error'));
      },
    );
    _durationSubscription = _player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current != null && duration != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
    _positionSubscription = _player.positionStream.listen(_onPositionChanged);
    _stallWatchdog = Timer.periodic(
      _stallCheckInterval,
      (_) => _recoverIfStalled(),
    );
  }

  final ProgressStore _progressStore;
  MediaControlsBridge? _mediaControls;
  final Future<PlaybackItem?> Function(PlaybackItem item)? refreshItem;
  final CatchUpDownloadCache? downloadCache;
  final AudioPlayer _player = AudioPlayer();
  @override
  final ValueNotifier<PlaybackItem?> currentItem = ValueNotifier(null);
  late final StreamSubscription<PlaybackEvent> _playbackSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final Timer _stallWatchdog;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionAdvancedAt = DateTime.now();
  Duration _lastWatchdogPosition = Duration.zero;
  Duration _restoredPosition = Duration.zero;
  bool _loadingItem = false;
  bool _recovering = false;
  bool _sourceLoaded = false;
  String? _activeCachePath;
  int _recoveryAttempt = 0;
  Timer? _recoveryRetryTimer;

  static const _stallCheckInterval = Duration(seconds: 5);
  static const _stallRecoveryAfter = Duration(seconds: 15);
  static const _maxAutomaticRecoveryAttempts = 3;

  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

  @override
  PlaybackState get playbackStateValue => playbackState.value;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  bool get isPlaying => _player.playing;

  @override
  Duration get position {
    if (!_sourceLoaded ||
        playbackState.value.processingState == AudioProcessingState.error) {
      return _restoredPosition;
    }
    return _player.position;
  }

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
    await _restoreItemShell(last);
  }

  Future<void> _loadItem(
    PlaybackItem item, {
    required bool playWhenReady,
    Duration? resumeOverride,
  }) async {
    if (item.audioUrl.isEmpty) {
      throw StateError('No audio URL is available for ${item.title}.');
    }
    _loadingItem = true;
    _sourceLoaded = false;
    _activeCachePath = null;
    try {
      currentItem.value = item;
      _lastPositionAdvancedAt = DateTime.now();
      _lastWatchdogPosition = resumeOverride ?? _restoredPosition;
      final media = item.toMediaItem();
      mediaItem.add(media);
      await _mediaControls?.updateItem(item);
      item = await _setAudioSourceWithRetry(item, media);
      final saved = item.isCatchUp ? _progressStore.progressFor(item.id) : null;
      final resume = resumeOverride ?? saved?.position ?? Duration.zero;
      final knownDuration = item.duration ?? _player.duration;
      if (resume > Duration.zero &&
          (knownDuration == null || resume < knownDuration)) {
        await _player.seek(resume);
      }
      _restoredPosition = resume;
      _lastWatchdogPosition = resume;
      await _progressStore.saveLastItem(item);
      _recoveryAttempt = 0;
    } finally {
      _loadingItem = false;
    }
    if (playWhenReady) {
      await _player.play();
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
  Future<void> play() async {
    final item = currentItem.value;
    final needsReload =
        item != null &&
        (!_sourceLoaded ||
            _player.processingState == ProcessingState.idle ||
            playbackState.value.processingState == AudioProcessingState.error);
    if (needsReload) {
      final resume = item.isCatchUp ? position : null;
      if (resume != null) {
        await _progressStore.saveProgress(item, resume);
      }
      await _loadItem(item, playWhenReady: true, resumeOverride: resume);
      return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _recoveryRetryTimer?.cancel();
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _recoveryRetryTimer?.cancel();
    await _saveProgress(force: true);
    await _player.stop();
    _sourceLoaded = false;
    _activeCachePath = null;
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
    if (!_sourceLoaded ||
        _player.processingState == ProcessingState.idle ||
        playbackState.value.processingState == AudioProcessingState.error) {
      _restoredPosition = position;
      await _progressStore.saveProgress(item!, position);
      _broadcastIdlePlaybackState(item, position);
      await _mediaControls?.updateTimeline(
        position: position,
        duration: duration,
        seekable: true,
      );
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
        current: position,
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
        current: position,
        delta: const Duration(seconds: -15),
        duration: duration,
      ),
    );
  }

  Future<void> dispose() async {
    _recoveryRetryTimer?.cancel();
    _stallWatchdog.cancel();
    await _saveProgress(force: true);
    await _playbackSubscription.cancel();
    await _durationSubscription.cancel();
    await _positionSubscription.cancel();
    await _player.dispose();
    await _mediaControls?.dispose();
    downloadCache?.dispose();
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
        position: position,
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
    if (!_sourceLoaded || _loadingItem) {
      return;
    }
    final item = currentItem.value;
    if (item?.isCatchUp ?? false) {
      _restoredPosition = position;
      if (position > _lastWatchdogPosition) {
        _lastWatchdogPosition = position;
        _lastPositionAdvancedAt = DateTime.now();
        _recoveryAttempt = 0;
      }
    }
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
    await _progressStore.saveProgress(item, position);
  }

  Future<void> _restoreItemShell(PlaybackItem item) async {
    currentItem.value = item;
    final media = item.toMediaItem();
    mediaItem.add(media);
    final saved = _progressStore.progressFor(item.id);
    final resume = saved?.position ?? Duration.zero;
    _restoredPosition = resume;
    _lastWatchdogPosition = resume;
    _lastPositionAdvancedAt = DateTime.now();
    _sourceLoaded = false;
    _broadcastIdlePlaybackState(item, resume);
    await _mediaControls?.updateItem(item);
    await _mediaControls?.updatePlaybackStatus(playing: false);
    await _mediaControls?.updateTimeline(
      position: resume,
      duration: duration,
      seekable: item.isCatchUp,
    );
  }

  void _broadcastIdlePlaybackState(PlaybackItem item, Duration position) {
    final isCatchUp = item.isCatchUp;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (isCatchUp) MediaControl.rewind,
          MediaControl.play,
          if (isCatchUp) MediaControl.fastForward,
          MediaControl.stop,
        ],
        systemActions: {
          if (isCatchUp) MediaAction.seek,
          if (isCatchUp) MediaAction.seekBackward,
          if (isCatchUp) MediaAction.seekForward,
        },
        androidCompactActionIndices: isCatchUp ? const [0, 1, 2] : const [0, 1],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: position,
        bufferedPosition: Duration.zero,
      ),
    );
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

  void _recoverIfStalled() {
    final item = currentItem.value;
    if (item == null ||
        item.isLive ||
        _loadingItem ||
        _recovering ||
        !_sourceLoaded ||
        !_player.playing ||
        _player.processingState == ProcessingState.completed) {
      return;
    }

    final currentDuration = duration;
    final currentPosition = position;
    if (currentDuration != null &&
        currentPosition >= currentDuration - const Duration(seconds: 2)) {
      return;
    }

    final stalledFor = DateTime.now().difference(_lastPositionAdvancedAt);
    if (stalledFor < _stallRecoveryAfter) {
      return;
    }

    unawaited(
      _recoverPlayback('position stalled for ${stalledFor.inSeconds}s'),
    );
  }

  Future<void> _recoverPlayback(String reason) async {
    final item = currentItem.value;
    if (item == null || item.isLive || _loadingItem || _recovering) {
      return;
    }

    final resume = position;
    _recovering = true;
    _recoveryRetryTimer?.cancel();
    debugPrint(
      'Recovering playback after $reason at ${resume.inMilliseconds}ms',
    );

    try {
      _restoredPosition = resume;
      await _progressStore.saveProgress(item, resume);
      await _player.stop();
      _sourceLoaded = false;
      _activeCachePath = null;
      _broadcastRecoveringPlaybackState(item, resume);
      await _loadItem(item, playWhenReady: true, resumeOverride: resume);
    } catch (error, stackTrace) {
      _sourceLoaded = false;
      _restoredPosition = resume;
      _recoveryAttempt += 1;
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
          updatePosition: resume,
          errorMessage: error.toString(),
        ),
      );
      debugPrint('Playback recovery failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRecoveryRetry(item, resume);
    } finally {
      _recovering = false;
    }
  }

  void _scheduleRecoveryRetry(PlaybackItem item, Duration resume) {
    if (_recoveryAttempt > _maxAutomaticRecoveryAttempts) {
      return;
    }

    final delay = Duration(seconds: 2 * _recoveryAttempt);
    _recoveryRetryTimer = Timer(delay, () {
      if (currentItem.value?.id != item.id) {
        return;
      }
      _restoredPosition = resume;
      unawaited(_recoverPlayback('automatic retry $_recoveryAttempt'));
    });
  }

  void _broadcastRecoveringPlaybackState(PlaybackItem item, Duration position) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (item.isCatchUp) MediaControl.rewind,
          MediaControl.pause,
          if (item.isCatchUp) MediaControl.fastForward,
          MediaControl.stop,
        ],
        systemActions: {
          if (item.isCatchUp) MediaAction.seek,
          if (item.isCatchUp) MediaAction.seekBackward,
          if (item.isCatchUp) MediaAction.seekForward,
        },
        androidCompactActionIndices: item.isCatchUp
            ? const [0, 1, 2]
            : const [0, 1],
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: position,
      ),
    );
  }

  Future<PlaybackItem> _setAudioSourceWithRetry(
    PlaybackItem item,
    MediaItem media,
  ) async {
    final cached = await _cachedFileFor(item);
    if (cached != null) {
      await _setCachedAudioSource(cached, media);
      return item;
    }

    try {
      await _setRemoteAudioSource(item, media);
      _startBackgroundDownload(item);
      return item;
    } catch (_) {
      final refreshed = await _tryRefreshItem(item);
      if (refreshed == null ||
          refreshed.audioUrl.isEmpty ||
          refreshed.audioUrl == item.audioUrl) {
        rethrow;
      }

      currentItem.value = refreshed;
      final refreshedMedia = refreshed.toMediaItem();
      mediaItem.add(refreshedMedia);
      await _mediaControls?.updateItem(refreshed);
      final refreshedCached = await _cachedFileFor(refreshed);
      if (refreshedCached != null) {
        await _setCachedAudioSource(refreshedCached, refreshedMedia);
        return refreshed;
      }

      await _setRemoteAudioSource(refreshed, refreshedMedia);
      _startBackgroundDownload(refreshed);
      return refreshed;
    }
  }

  Future<File?> _cachedFileFor(PlaybackItem item) async {
    try {
      return await downloadCache?.cachedFileFor(item);
    } catch (error, stackTrace) {
      debugPrint('Could not inspect cached audio: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _setRemoteAudioSource(PlaybackItem item, MediaItem media) async {
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(item.audioUrl), tag: media),
    );
    _sourceLoaded = true;
    _activeCachePath = null;
  }

  Future<void> _setCachedAudioSource(File file, MediaItem media) async {
    await _player.setAudioSource(AudioSource.uri(file.uri, tag: media));
    _sourceLoaded = true;
    _activeCachePath = file.path;
  }

  void _startBackgroundDownload(PlaybackItem item) {
    downloadCache?.ensureDownloadStarted(
      item,
      onComplete: (file) {
        unawaited(_switchToCachedFileWhenReady(item, file));
      },
    );
  }

  Future<void> _switchToCachedFileWhenReady(
    PlaybackItem item,
    File file,
  ) async {
    for (var attempt = 0; attempt < 10 && _loadingItem; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _switchToCachedFileIfCurrent(item, file);
  }

  Future<void> _switchToCachedFileIfCurrent(
    PlaybackItem item,
    File file,
  ) async {
    if (currentItem.value?.id != item.id ||
        !item.isCatchUp ||
        !_sourceLoaded ||
        _loadingItem ||
        _recovering ||
        _activeCachePath == file.path ||
        !await file.exists()) {
      return;
    }

    final resume = position;
    final wasPlaying = _player.playing;
    final media = mediaItem.valueOrNull ?? item.toMediaItem();
    _loadingItem = true;
    try {
      debugPrint('Switching catch-up playback to cached audio: ${file.path}');
      await _setCachedAudioSource(file, media);
      final knownDuration = duration;
      if (resume > Duration.zero &&
          (knownDuration == null || resume < knownDuration)) {
        await _player.seek(resume);
      }
      _restoredPosition = resume;
      _lastWatchdogPosition = resume;
      _lastPositionAdvancedAt = DateTime.now();
      await _progressStore.saveProgress(item, resume);
      if (wasPlaying && currentItem.value?.id == item.id) {
        await _player.play();
      } else {
        await _mediaControls?.updatePlaybackStatus(playing: false);
      }
    } catch (error, stackTrace) {
      debugPrint('Could not switch to cached audio: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _loadingItem = false;
    }
  }

  Future<PlaybackItem?> _tryRefreshItem(PlaybackItem item) async {
    final refresh = refreshItem;
    if (refresh == null || !item.isCatchUp) {
      return null;
    }
    try {
      return await refresh(item);
    } catch (error, stackTrace) {
      debugPrint('Could not refresh playback item: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }
}
