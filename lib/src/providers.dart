import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'data/progress_store.dart';
import 'data/station_repository.dart';
import 'data/talksport_api.dart';
import 'models/now_playing.dart';
import 'models/schedule_day.dart';
import 'models/station.dart';
import 'playback/playback_controller.dart';

final stationRepositoryProvider = Provider<StationRepository>(
  (ref) => const StationRepository(),
);

final talkSportApiProvider = Provider<TalkSportApi>((ref) => TalkSportApi());

final progressStoreProvider = Provider<ProgressStore>(
  (ref) => throw UnimplementedError('ProgressStore must be overridden.'),
);

final playbackControllerProvider = Provider<PlaybackController>(
  (ref) => throw UnimplementedError('Playback controller must be overridden.'),
);

final selectedStationProvider = StateProvider<Station>((ref) {
  return ref.watch(stationRepositoryProvider).stations.first;
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedDayNumberProvider = StateProvider<int>((ref) => 0);

final scheduleProvider =
    FutureProvider.autoDispose.family<List<ScheduleDay>, String>(
  (ref, stationSlug) {
    return ref.watch(talkSportApiProvider).fetchSchedule(stationSlug);
  },
);

final nowPlayingProvider =
    FutureProvider.autoDispose.family<NowPlaying, String>((ref, stationSlug) {
  ref.watch(_nowPlayingTickerProvider);
  return ref.watch(talkSportApiProvider).fetchNowPlaying(stationSlug);
});

final _nowPlayingTickerProvider = StreamProvider.autoDispose<void>((ref) {
  return Stream<void>.periodic(const Duration(minutes: 1));
});
