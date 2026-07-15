import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'src/app.dart';
import 'src/data/progress_store.dart';
import 'src/data/station_repository.dart';
import 'src/data/talksport_api.dart';
import 'src/playback/catch_up_download_cache.dart';
import 'src/playback/live_timeshift_session.dart';
import 'src/playback/playback_item_refresher.dart';
import 'src/playback/talksport_audio_handler.dart';
import 'src/playback/windows_media_controls.dart';
import 'src/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    JustAudioMediaKit.title = 'talkSPORT Companion';
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  }

  final progressStore = await ProgressStore.create();
  const stationRepository = StationRepository();
  final talkSportApi = TalkSportApi();
  final playbackItemRefresher = PlaybackItemRefresher(
    api: talkSportApi,
    stationRepository: stationRepository,
  );
  final downloadCache = CatchUpDownloadCache(
    rootDirectory: await CatchUpDownloadCache.defaultRootDirectory(),
  );
  final liveTimeshiftManager = LiveTimeshiftManager(
    rootDirectory: await LiveTimeshiftManager.defaultRootDirectory(),
  );
  unawaited(_cleanExpiredCatchUpAudio(downloadCache));
  unawaited(liveTimeshiftManager.cleanStaleSessions());
  final audioHandler = await _createPlaybackHandler(
    progressStore,
    playbackItemRefresher,
    downloadCache,
    liveTimeshiftManager,
  );
  WidgetsBinding.instance.addObserver(
    _AppLifecycleObserver(audioHandler, talkSportApi, stationRepository),
  );

  runApp(
    ProviderScope(
      overrides: [
        stationRepositoryProvider.overrideWithValue(stationRepository),
        talkSportApiProvider.overrideWithValue(talkSportApi),
        progressStoreProvider.overrideWithValue(progressStore),
        playbackControllerProvider.overrideWithValue(audioHandler),
      ],
      child: const TalkSportApp(),
    ),
  );

  _restorePreviousPlayback(audioHandler);

  if (Platform.isWindows) {
    _attachWindowsMediaControls(audioHandler);
  }
}

Future<void> _cleanExpiredCatchUpAudio(
  CatchUpDownloadCache downloadCache,
) async {
  try {
    await downloadCache.cleanExpired();
  } catch (error, stackTrace) {
    debugPrint('Could not clean cached catch-up audio: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver(
    this.audioHandler,
    this.talkSportApi,
    this.stationRepository,
  );

  final TalkSportAudioHandler audioHandler;
  final TalkSportApi talkSportApi;
  final StationRepository stationRepository;
  DateTime? _inactiveSince;
  DateTime _lastMetadataRecoveryAt = DateTime.now();
  DateTime _lastObservedDate = _dateOnly(DateTime.now());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final inactiveSince = _inactiveSince;
      final currentDate = _dateOnly(now);
      final wasAway =
          inactiveSince != null &&
          now.difference(inactiveSince) >= const Duration(minutes: 1);
      final recoveryIsStale =
          now.difference(_lastMetadataRecoveryAt) >= const Duration(minutes: 5);
      final dateChanged = currentDate != _lastObservedDate;
      _inactiveSince = null;
      _lastObservedDate = currentDate;

      if (wasAway || recoveryIsStale || dateChanged) {
        _lastMetadataRecoveryAt = now;
        unawaited(_recoverMetadata());
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _inactiveSince ??= DateTime.now();
      unawaited(audioHandler.flushProgress());
    }
  }

  Future<void> _recoverMetadata() async {
    try {
      await talkSportApi.recoverAfterResume(
        stationRepository.stations.map((station) => station.slug),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not refresh metadata after resume: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

Future<TalkSportAudioHandler> _createPlaybackHandler(
  ProgressStore progressStore,
  PlaybackItemRefresher playbackItemRefresher,
  CatchUpDownloadCache downloadCache,
  LiveTimeshiftManager liveTimeshiftManager,
) async {
  if (Platform.isAndroid) {
    return AudioService.init<TalkSportAudioHandler>(
      builder: () => TalkSportAudioHandler(
        progressStore,
        null,
        refreshItem: playbackItemRefresher.refresh,
        downloadCache: downloadCache,
        liveTimeshiftManager: liveTimeshiftManager,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.ben.talksport.audio',
        androidNotificationChannelName: 'talkSPORT playback',
        androidStopForegroundOnPause: false,
        fastForwardInterval: Duration(seconds: 15),
        rewindInterval: Duration(seconds: 15),
      ),
    );
  }

  return TalkSportAudioHandler(
    progressStore,
    null,
    refreshItem: playbackItemRefresher.refresh,
    downloadCache: downloadCache,
    liveTimeshiftManager: liveTimeshiftManager,
    configureSession: false,
  );
}

void _attachWindowsMediaControls(TalkSportAudioHandler audioHandler) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final controls = await WindowsMediaControls.create();
      if (controls != null) {
        await audioHandler.attachMediaControls(controls);
      }
    } catch (error, stackTrace) {
      debugPrint('Windows media controls unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  });
}

void _restorePreviousPlayback(TalkSportAudioHandler audioHandler) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await audioHandler.restoreLastItem();
    } catch (error, stackTrace) {
      debugPrint('Could not restore previous playback: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  });
}
