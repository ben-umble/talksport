import 'dart:async';

import '../data/station_repository.dart';
import '../data/talksport_api.dart';
import '../models/playback_item.dart';
import '../models/schedule_day.dart';
import '../models/show.dart';

class PlaybackItemRefresher {
  const PlaybackItemRefresher({
    required this.api,
    required this.stationRepository,
    this.timeout = const Duration(seconds: 12),
  });

  final TalkSportApi api;
  final StationRepository stationRepository;
  final Duration timeout;

  Future<PlaybackItem?> refresh(PlaybackItem item) async {
    if (!item.isCatchUp) {
      return item;
    }

    final schedule = await api
        .fetchSchedule(item.stationSlug, allowCached: false)
        .timeout(timeout, onTimeout: () => const <ScheduleDay>[]);
    final show = _findShow(schedule, item.id);
    if (show == null || !show.hasRecording) {
      return null;
    }

    return PlaybackItem.catchUp(
      stationRepository.bySlug(item.stationSlug),
      show,
    );
  }

  Show? _findShow(List<ScheduleDay> schedule, String showId) {
    for (final day in schedule) {
      for (final show in day.shows) {
        if (show.id == showId) {
          return show;
        }
      }
    }
    return null;
  }
}
