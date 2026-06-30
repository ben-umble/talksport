import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talksport_companion/src/data/talksport_api.dart';
import 'package:talksport_companion/src/data/talksport_page_scraper.dart';
import 'package:talksport_companion/src/models/now_playing.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';
import 'package:talksport_companion/src/models/show.dart';

void main() {
  test(
    'returns stale cached schedule while refreshing in the background',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(hours: 10),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
          ),
        ),
      });
      final scraper = _FailingScraper();
      final api = TalkSportApi(
        client: MockClient((_) async => throw StateError('HTTP was used')),
        pageScraper: scraper,
      );

      final schedule = await api.fetchSchedule('talksport');

      expect(schedule.single.shows.single.title, 'Cached White & Jordan');
      expect(scraper.calls, 1);
    },
  );

  test(
    'returns stale cached now-playing while refreshing in the background',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(hours: 10),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
          ),
        ),
      });
      final scraper = _FailingScraper();
      final api = TalkSportApi(
        client: MockClient((_) async => throw StateError('HTTP was used')),
        pageScraper: scraper,
      );

      final nowPlaying = await api.fetchNowPlaying('talksport');

      expect(nowPlaying.title, 'Cached live show');
      expect(scraper.calls, 1);
    },
  );
}

Map<String, dynamic> _cachedPayloadJson({
  required Duration age,
  required String nowPlayingTitle,
  required String scheduleTitle,
}) {
  final now = DateTime.now();
  return {
    'updatedAtMs': now.subtract(age).millisecondsSinceEpoch,
    'onAirNow': _nowPlaying(nowPlayingTitle).toJson(),
    'schedule': [_scheduleDay(scheduleTitle).toJson()],
  };
}

NowPlaying _nowPlaying(String title) {
  return NowPlaying(
    title: title,
    id: 'live',
    description: 'Cached live description.',
    programmeTitle: title,
    images: const {},
    startTime: DateTime.utc(2026, 6, 30, 10),
    endTime: DateTime.utc(2026, 6, 30, 13),
    liveVideo: const {},
    hasLiveStream: false,
    nextShow: null,
    stationSlug: 'talksport',
    stationId: 'talksport',
    type: 'live',
  );
}

ScheduleDay _scheduleDay(String title) {
  return ScheduleDay(
    date: '2026-06-30',
    itemId: 'today',
    dayNumber: 0,
    shows: [
      Show(
        id: 'show-1',
        title: title,
        programmeTitle: title,
        startTime: DateTime.utc(2026, 6, 30, 10),
        endTime: DateTime.utc(2026, 6, 30, 13),
        description: 'Cached show description.',
        images: const {},
        recording: null,
        liveVideo: const {},
        stationId: 'talksport',
        stationSlug: 'talksport',
      ),
    ],
  );
}

class _FailingScraper implements TalkSportPageScraper {
  int calls = 0;

  @override
  Future<TalkSportPagePayload> fetch(String stationSlug) async {
    calls++;
    throw StateError('Refresh failed');
  }
}
