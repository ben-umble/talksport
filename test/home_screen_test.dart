import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/data/progress_store.dart';
import 'package:talksport_companion/src/data/talksport_api.dart';
import 'package:talksport_companion/src/models/now_playing.dart';
import 'package:talksport_companion/src/models/playback_item.dart';
import 'package:talksport_companion/src/models/recording.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';
import 'package:talksport_companion/src/models/show.dart';
import 'package:talksport_companion/src/playback/playback_controller.dart';
import 'package:talksport_companion/src/providers.dart';
import 'package:talksport_companion/src/ui/home_screen.dart';

void main() {
  testWidgets('shows live panel and catch-up rows', (tester) async {
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          talkSportApiProvider.overrideWithValue(_FakeTalkSportApi()),
          progressStoreProvider.overrideWithValue(ProgressStore.memory()),
          playbackControllerProvider.overrideWithValue(handler),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('talkSPORT'), findsWidgets);
    expect(find.text('World Cup GameDay Live'), findsOneWidget);
    expect(find.text('White & Jordan'), findsOneWidget);
    expect(find.text('Search shows'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
  });
}

class _FakePlaybackController implements PlaybackController {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  PlaybackState _state = PlaybackState(
    processingState: AudioProcessingState.idle,
  );

  @override
  final ValueNotifier<PlaybackItem?> currentItem = ValueNotifier(null);

  @override
  Duration? duration;

  @override
  Duration position = Duration.zero;

  @override
  Stream<PlaybackState> get playbackStateStream => _stateController.stream;

  @override
  PlaybackState get playbackStateValue => _state;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Future<void> fastForward() async {}

  @override
  Future<void> pause() async {
    _state = _state.copyWith(playing: false);
    _stateController.add(_state);
  }

  @override
  Future<void> play() async {
    _state = _state.copyWith(playing: true);
    _stateController.add(_state);
  }

  @override
  Future<void> playItem(PlaybackItem item) async {
    currentItem.value = item;
    duration = item.duration;
    await play();
  }

  @override
  Future<void> replayLastItem() async {}

  @override
  Future<void> rewind() async {}

  @override
  Future<void> seek(Duration position) async {
    this.position = position;
    _positionController.add(position);
  }

  @override
  Future<void> stop() async {
    currentItem.value = null;
    await pause();
  }

  Future<void> dispose() async {
    currentItem.dispose();
    await _stateController.close();
    await _positionController.close();
  }
}

class _FakeTalkSportApi extends TalkSportApi {
  @override
  Future<List<ScheduleDay>> fetchSchedule(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    return [
      ScheduleDay(
        date: '2026-06-29',
        dayNumber: 0,
        itemId: 'today',
        shows: [
          _show(
            id: 'white-and-jordan',
            title: 'White & Jordan',
            recording: const Recording(
              url: 'https://example.test/white-and-jordan.mp3',
              duration: 10800000,
            ),
          ),
          _show(id: 'future', title: 'Later Show'),
        ],
      ),
    ];
  }

  @override
  Future<NowPlaying> fetchNowPlaying(String stationSlug) async {
    return NowPlaying(
      title: 'World Cup GameDay Live',
      id: 'live',
      description: 'Live commentary from the World Cup.',
      programmeTitle: 'The Phone In',
      images: const {},
      startTime: DateTime.utc(2026, 6, 29, 15),
      endTime: DateTime.utc(2026, 6, 29, 19, 30),
      liveVideo: const {},
      hasLiveStream: false,
      nextShow: null,
      stationSlug: stationSlug,
      stationId: stationSlug,
      type: 'live',
    );
  }
}

Show _show({required String id, required String title, Recording? recording}) {
  return Show(
    id: id,
    title: title,
    programmeTitle: title,
    startTime: DateTime.utc(2026, 6, 29, 12),
    endTime: DateTime.utc(2026, 6, 29, 15),
    description: 'A test show.',
    images: const {},
    recording: recording,
    liveVideo: const {},
    stationId: 'talksport',
    stationSlug: 'talksport',
  );
}
