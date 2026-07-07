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

final talkSportApiProvider = Provider<TalkSportApi>((ref) {
  final api = TalkSportApi();
  ref.onDispose(api.dispose);
  return api;
});

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

final scheduleProvider = FutureProvider.autoDispose
    .family<List<ScheduleDay>, String>((ref, stationSlug) {
      ref.watch(_scheduleTickerProvider);
      ref.watch(_scheduleUpdatesProvider(stationSlug));
      return ref.watch(talkSportApiProvider).fetchSchedule(stationSlug);
    });

final nowPlayingProvider = FutureProvider.autoDispose
    .family<NowPlaying, String>((ref, stationSlug) {
      ref.watch(_nowPlayingTickerProvider);
      return ref.watch(talkSportApiProvider).fetchNowPlaying(stationSlug);
    });

final _nowPlayingTickerProvider = StreamProvider.autoDispose<void>((ref) {
  return Stream<void>.periodic(const Duration(minutes: 1));
});

final _scheduleTickerProvider = StreamProvider.autoDispose<void>((ref) {
  return Stream<void>.periodic(const Duration(seconds: 15));
});

final _scheduleUpdatesProvider = StreamProvider.autoDispose
    .family<void, String>((ref, stationSlug) {
      final api = ref.watch(talkSportApiProvider);
      return api.scheduleUpdates
          .where((updatedStationSlug) => updatedStationSlug == stationSlug)
          .map((_) {});
    });
