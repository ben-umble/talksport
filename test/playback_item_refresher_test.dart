import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/data/station_repository.dart';
import 'package:talksport_companion/src/data/talksport_api.dart';
import 'package:talksport_companion/src/models/playback_item.dart';
import 'package:talksport_companion/src/models/recording.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';
import 'package:talksport_companion/src/models/show.dart';
import 'package:talksport_companion/src/playback/playback_item_refresher.dart';

void main() {
  test(
    'refreshes a remembered catch-up item with the current recording URL',
    () async {
      final api = _FakeTalkSportApi();
      final refresher = PlaybackItemRefresher(
        api: api,
        stationRepository: const StationRepository(),
      );
      final stale = PlaybackItem(
        id: 'white-and-jordan',
        kind: PlaybackKind.catchUp,
        stationSlug: 'talksport',
        stationName: 'talkSPORT',
        title: 'White & Jordan',
        subtitle: 'talkSPORT',
        description: 'Old description.',
        audioUrl: 'https://example.test/old.mp3',
        imageUrl: null,
        duration: const Duration(hours: 3),
      );

      final refreshed = await refresher.refresh(stale);

      expect(api.lastAllowCached, isFalse);
      expect(refreshed, isNotNull);
      expect(refreshed!.audioUrl, 'https://example.test/fresh.mp3');
      expect(refreshed.title, 'White & Jordan');
    },
  );
}

class _FakeTalkSportApi extends TalkSportApi {
  bool? lastAllowCached;

  @override
  Future<List<ScheduleDay>> fetchSchedule(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    lastAllowCached = allowCached;
    return [
      ScheduleDay(
        date: '2026-06-30',
        itemId: 'today',
        dayNumber: 0,
        shows: [
          Show(
            id: 'white-and-jordan',
            title: 'White & Jordan',
            programmeTitle: 'White & Jordan',
            startTime: DateTime.utc(2026, 6, 30, 10),
            endTime: DateTime.utc(2026, 6, 30, 13),
            description: 'Fresh description.',
            images: const {},
            recording: const Recording(
              url: 'https://example.test/fresh.mp3',
              duration: 10800000,
            ),
            liveVideo: const {},
            stationId: stationSlug,
            stationSlug: stationSlug,
          ),
        ],
      ),
    ];
  }
}
