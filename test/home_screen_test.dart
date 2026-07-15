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
import 'package:talksport_companion/src/playback/live_timeshift_state.dart';
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
    expect(find.text('Today 29 Jun'), findsOneWidget);
    expect(find.text('Yesterday 28 Jun'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
  });

  testWidgets('shows catch-up date and dock skip controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    await handler.playItem(
      PlaybackItem(
        id: '20260629-white-and-jordan',
        kind: PlaybackKind.catchUp,
        stationSlug: 'talksport',
        stationName: 'talkSPORT',
        title: 'White & Jordan',
        subtitle: 'talkSPORT',
        description: '',
        audioUrl: 'https://example.test/audio.mp3',
        imageUrl: null,
        duration: const Duration(hours: 3),
        showDate: DateTime.utc(2026, 6, 29),
      ),
    );
    await tester.pump();

    expect(find.text('talkSPORT - Mon 29 Jun 2026'), findsOneWidget);
    expect(find.text('15s'), findsNWidgets(2));
    expect(find.text('30s'), findsNWidgets(2));
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
  });

  testWidgets('shows a seekable delayed-live timeline and Go Live action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);
    handler.currentItem.value = const PlaybackItem(
      id: 'live:talksport',
      kind: PlaybackKind.live,
      stationSlug: 'talksport',
      stationName: 'talkSPORT',
      title: 'White & Jordan',
      subtitle: 'Live on talkSPORT',
      description: '',
      audioUrl: 'https://example.test/live',
      imageUrl: null,
      duration: null,
    );
    handler.position = const Duration(minutes: 9, seconds: 15);
    handler.liveTimeshiftState.value = const LiveTimeshiftState(
      phase: LiveTimeshiftPhase.ready,
      bufferStart: Duration(minutes: 1),
      liveEdge: Duration(minutes: 10),
      playbackPosition: Duration(minutes: 9, seconds: 15),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackControllerProvider.overrideWithValue(handler)],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(),
            bottomNavigationBar: PlaybackDock(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('00:45 BEHIND'), findsOneWidget);
    expect(find.text('Go Live'), findsOneWidget);
    expect(find.text('15s'), findsNWidgets(2));

    await tester.tap(find.text('Go Live'));
    await tester.pump();
    expect(handler.goLiveCalls, 1);
  });

  testWidgets('keeps delayed-live controls usable on a compact layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);
    handler.currentItem.value = const PlaybackItem(
      id: 'live:talksport',
      kind: PlaybackKind.live,
      stationSlug: 'talksport',
      stationName: 'talkSPORT',
      title: 'White & Jordan',
      subtitle: 'Live on talkSPORT',
      description: '',
      audioUrl: 'https://example.test/live',
      imageUrl: null,
      duration: null,
    );
    handler.position = const Duration(minutes: 9, seconds: 15);
    handler.liveTimeshiftState.value = const LiveTimeshiftState(
      phase: LiveTimeshiftPhase.ready,
      bufferStart: Duration(minutes: 1),
      liveEdge: Duration(minutes: 10),
      playbackPosition: Duration(minutes: 9, seconds: 15),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackControllerProvider.overrideWithValue(handler)],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(),
            bottomNavigationBar: PlaybackDock(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('00:45 BEHIND'), findsOneWidget);
    expect(find.byIcon(Icons.sensors_rounded), findsOneWidget);
    expect(find.text('15s'), findsNWidgets(2));

    await tester.tap(find.text('White & Jordan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('4m'), findsOneWidget);
  });

  testWidgets('refresh button requests fresh catch-up schedule', (
    tester,
  ) async {
    final api = _FakeTalkSportApi();
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          talkSportApiProvider.overrideWithValue(api),
          progressStoreProvider.overrideWithValue(ProgressStore.memory()),
          playbackControllerProvider.overrideWithValue(handler),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.forcedScheduleRefreshes, 0);
    await tester.tap(find.byKey(const Key('catch-up-refresh-button')));
    await tester.pumpAndSettle();

    expect(api.forcedScheduleRefreshes, 1);
    expect(api.forcedNowPlayingRefreshes, 1);
  });

  testWidgets('refresh button applies fresh catch-up rows immediately', (
    tester,
  ) async {
    final api = _FakeTalkSportApi(
      forcedSchedule: [
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
            _show(
              id: 'fresh-show',
              title: 'Freshly Available Show',
              recording: const Recording(
                url: 'https://example.test/fresh-show.mp3',
                duration: 3600000,
              ),
            ),
          ],
        ),
      ],
    );
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          talkSportApiProvider.overrideWithValue(api),
          progressStoreProvider.overrideWithValue(ProgressStore.memory()),
          playbackControllerProvider.overrideWithValue(handler),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Freshly Available Show'), findsNothing);
    expect(find.text('1 available on Today 29 Jun'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catch-up-refresh-button')));
    await tester.pumpAndSettle();

    expect(find.text('Freshly Available Show'), findsOneWidget);
    expect(
      find.textContaining('2 available on Today 29 Jun - Updated'),
      findsOneWidget,
    );
  });

  testWidgets('refresh button ignores live info refresh failures', (
    tester,
  ) async {
    final api = _FakeTalkSportApi(failForcedNowPlaying: true);
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          talkSportApiProvider.overrideWithValue(api),
          progressStoreProvider.overrideWithValue(ProgressStore.memory()),
          playbackControllerProvider.overrideWithValue(handler),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catch-up-refresh-button')));
    await tester.pumpAndSettle();

    expect(api.forcedScheduleRefreshes, 1);
    expect(api.forcedNowPlayingRefreshes, 1);
    expect(find.text('Could not refresh catch-up yet.'), findsNothing);
  });

  testWidgets('refresh button shows an error when catch-up refresh fails', (
    tester,
  ) async {
    final api = _FakeTalkSportApi(failForcedSchedule: true);
    final handler = _FakePlaybackController();
    addTearDown(handler.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          talkSportApiProvider.overrideWithValue(api),
          progressStoreProvider.overrideWithValue(ProgressStore.memory()),
          playbackControllerProvider.overrideWithValue(handler),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catch-up-refresh-button')));
    await tester.pumpAndSettle();

    expect(api.forcedScheduleRefreshes, 1);
    expect(api.forcedNowPlayingRefreshes, 0);
    expect(find.text('Could not refresh catch-up yet.'), findsOneWidget);
  });
}

class _FakePlaybackController implements PlaybackController {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  PlaybackState _state = PlaybackState(
    processingState: AudioProcessingState.idle,
  );
  int goLiveCalls = 0;

  @override
  final ValueNotifier<PlaybackItem?> currentItem = ValueNotifier(null);

  @override
  final ValueNotifier<LiveTimeshiftState> liveTimeshiftState = ValueNotifier(
    const LiveTimeshiftState.idle(),
  );

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
  Future<void> goLive() async {
    goLiveCalls += 1;
  }

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
    liveTimeshiftState.dispose();
    await _stateController.close();
    await _positionController.close();
  }
}

class _FakeTalkSportApi extends TalkSportApi {
  _FakeTalkSportApi({
    this.failForcedSchedule = false,
    this.failForcedNowPlaying = false,
    this.forcedSchedule,
  });

  final bool failForcedSchedule;
  final bool failForcedNowPlaying;
  final List<ScheduleDay>? forcedSchedule;
  int forcedScheduleRefreshes = 0;
  int forcedNowPlayingRefreshes = 0;

  @override
  Future<List<ScheduleDay>> fetchSchedule(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    if (!allowCached) {
      forcedScheduleRefreshes++;
      if (failForcedSchedule) {
        throw StateError('Schedule refresh failed.');
      }
      final forced = forcedSchedule;
      if (forced != null) {
        return forced;
      }
    }
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
      ScheduleDay(
        date: '2026-06-28',
        dayNumber: -1,
        itemId: 'yesterday',
        shows: [
          _show(
            id: 'yesterday-show',
            title: 'Yesterday Show',
            recording: const Recording(
              url: 'https://example.test/yesterday-show.mp3',
              duration: 3600000,
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Future<NowPlaying> fetchNowPlaying(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    if (!allowCached) {
      forcedNowPlayingRefreshes++;
      if (failForcedNowPlaying) {
        throw StateError('Now playing refresh failed.');
      }
    }
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
