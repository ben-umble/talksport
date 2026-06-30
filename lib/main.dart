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
  final audioHandler = await _createPlaybackHandler(
    progressStore,
    playbackItemRefresher,
  );
  WidgetsBinding.instance.addObserver(_PlaybackLifecycleObserver(audioHandler));

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

class _PlaybackLifecycleObserver with WidgetsBindingObserver {
  _PlaybackLifecycleObserver(this.audioHandler);

  final TalkSportAudioHandler audioHandler;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(audioHandler.flushProgress());
    }
  }
}

Future<TalkSportAudioHandler> _createPlaybackHandler(
  ProgressStore progressStore,
  PlaybackItemRefresher playbackItemRefresher,
) async {
  if (Platform.isAndroid) {
    return AudioService.init<TalkSportAudioHandler>(
      builder: () => TalkSportAudioHandler(
        progressStore,
        null,
        refreshItem: playbackItemRefresher.refresh,
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
