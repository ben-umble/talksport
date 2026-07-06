import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talksport_companion/src/data/talksport_api.dart';
import 'package:talksport_companion/src/data/talksport_page_scraper.dart';
import 'package:talksport_companion/src/models/now_playing.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';
import 'package:talksport_companion/src/models/show.dart';

void main() {
  test('uses the direct schedule API before the WebView fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final scraper = _FailingScraper();
    final api = TalkSportApi(
      client: MockClient((request) async {
        expect(request.url.path, '/play/api/schedule/talksport');
        return http.Response(
          jsonEncode([_scheduleDay('API show').toJson()]),
          200,
        );
      }),
      pageScraper: scraper,
    );

    final schedule = await api.fetchSchedule('talksport');

    expect(schedule.single.shows.single.title, 'API show');
    expect(scraper.calls, 0);
  });

  test('uses the direct now-playing API before the WebView fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final scraper = _FailingScraper();
    final api = TalkSportApi(
      client: MockClient((request) async {
        expect(request.url.path, '/play/api/onAirNow/talksport');
        return http.Response(
          jsonEncode(_nowPlaying('API live show').toJson()),
          200,
        );
      }),
      pageScraper: scraper,
    );

    final nowPlaying = await api.fetchNowPlaying('talksport');

    expect(nowPlaying.title, 'API live show');
    expect(scraper.calls, 0);
  });

  test(
    'returns current-day cached schedule without blocking on refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(minutes: 1),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
            scheduleDate: _todayKey(),
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
      expect(scraper.calls, 0);
    },
  );

  test(
    'normalizes stale-date cached schedule instead of calling it today',
    () async {
      final cachedDate = DateTime.now().subtract(const Duration(days: 3));
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(minutes: 1),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Old cached show',
            scheduleDate: _dateKey(cachedDate),
          ),
        ),
      });
      final scraper = _FailingScraper();
      final api = TalkSportApi(
        client: MockClient((_) async => throw StateError('HTTP was used')),
        pageScraper: scraper,
      );

      final schedule = await api.fetchSchedule('talksport');

      expect(schedule.single.shows.single.title, 'Old cached show');
      expect(schedule.single.dayNumber, -3);
      expect(scraper.calls, 0);
    },
  );

  test('suppresses the direct API after a verification page', () async {
    SharedPreferences.setMockInitialValues({});
    var httpCalls = 0;
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'Fresh current show',
      nowPlayingTitle: 'Fresh live show',
    );
    final api = TalkSportApi(
      client: MockClient((_) async {
        httpCalls++;
        return http.Response(
          '<!DOCTYPE html><html><body>Verification</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }),
      pageScraper: scraper,
    );

    final firstSchedule = await api.fetchSchedule(
      'talksport',
      allowCached: false,
    );
    final secondSchedule = await api.fetchSchedule(
      'talksport',
      allowCached: false,
    );

    expect(firstSchedule.single.shows.single.title, 'Fresh current show');
    expect(secondSchedule.single.shows.single.title, 'Fresh current show');
    expect(httpCalls, 1);
    expect(scraper.calls, 2);
  });

  test(
    'returns fresh cached now-playing without blocking on refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(minutes: 1),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
            scheduleDate: _todayKey(),
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
      expect(scraper.calls, 0);
    },
  );

  test('does not return old cached now-playing', () async {
    SharedPreferences.setMockInitialValues({
      'talksport.metadata.talksport': jsonEncode(
        _cachedPayloadJson(
          age: const Duration(hours: 10),
          nowPlayingTitle: 'Old cached live show',
          scheduleTitle: 'Cached White & Jordan',
          scheduleDate: _todayKey(),
        ),
      ),
    });
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'Fresh current show',
      nowPlayingTitle: 'Fresh live show',
    );
    final api = TalkSportApi(
      client: MockClient((_) async => http.Response('<html></html>', 200)),
      pageScraper: scraper,
    );

    final nowPlaying = await api.fetchNowPlaying('talksport');

    expect(nowPlaying.title, 'Fresh live show');
    expect(scraper.calls, 1);
  });
}

Map<String, dynamic> _cachedPayloadJson({
  required Duration age,
  required String nowPlayingTitle,
  required String scheduleTitle,
  required String scheduleDate,
}) {
  final now = DateTime.now();
  return {
    'updatedAtMs': now.subtract(age).millisecondsSinceEpoch,
    'onAirNow': _nowPlaying(nowPlayingTitle).toJson(),
    'schedule': [_scheduleDay(scheduleTitle, date: scheduleDate).toJson()],
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

ScheduleDay _scheduleDay(String title, {String? date}) {
  return ScheduleDay(
    date: date ?? _todayKey(),
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

String _todayKey() => _dateKey(DateTime.now());

String _dateKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class _FailingScraper implements TalkSportPageScraper {
  int calls = 0;

  @override
  Future<TalkSportPagePayload> fetch(String stationSlug) async {
    calls++;
    throw StateError('Refresh failed');
  }
}

class _SuccessfulScraper implements TalkSportPageScraper {
  _SuccessfulScraper({
    required this.scheduleTitle,
    required this.nowPlayingTitle,
  });

  final String scheduleTitle;
  final String nowPlayingTitle;
  int calls = 0;

  @override
  Future<TalkSportPagePayload> fetch(String stationSlug) async {
    calls++;
    return TalkSportPagePayload(
      nowPlaying: _nowPlaying(nowPlayingTitle),
      schedule: [_scheduleDay(scheduleTitle)],
    );
  }
}
