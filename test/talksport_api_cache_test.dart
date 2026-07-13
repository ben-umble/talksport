import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talksport_companion/src/data/talksport_api.dart';
import 'package:talksport_companion/src/data/talksport_page_scraper.dart';
import 'package:talksport_companion/src/models/now_playing.dart';
import 'package:talksport_companion/src/models/recording.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';
import 'package:talksport_companion/src/models/show.dart';

void main() {
  test('uses direct schedule metadata before the WebView', () async {
    SharedPreferences.setMockInitialValues({});
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'WebView show',
      nowPlayingTitle: 'WebView live show',
    );
    final api = TalkSportApi(
      client: MockClient((request) async {
        expect(request.url.queryParameters['refresh'], isNotEmpty);
        if (request.url.path.contains('/schedule/')) {
          return http.Response(
            jsonEncode([_scheduleDay('API show').toJson()]),
            200,
          );
        }
        return http.Response(
          jsonEncode(_nowPlaying('API live show').toJson()),
          200,
        );
      }),
      pageScraper: scraper,
    );

    final schedule = await api.fetchSchedule('talksport');

    expect(schedule.single.shows.single.title, 'API show');
    expect(scraper.calls, 0);
  });

  test(
    'falls back to WebView schedule metadata after verification HTML',
    () async {
      SharedPreferences.setMockInitialValues({});
      final scraper = _SuccessfulScraper(
        scheduleTitle: 'WebView show',
        nowPlayingTitle: 'WebView live show',
      );
      final api = TalkSportApi(
        client: MockClient((_) async => http.Response('<html></html>', 200)),
        pageScraper: scraper,
      );

      final schedule = await api.fetchSchedule('talksport');

      expect(schedule.single.shows.single.title, 'WebView show');
      expect(scraper.calls, 1);
    },
  );

  test('uses direct now-playing metadata before the WebView', () async {
    SharedPreferences.setMockInitialValues({});
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'WebView show',
      nowPlayingTitle: 'WebView live show',
    );
    final api = TalkSportApi(
      client: MockClient((request) async {
        expect(request.url.path, '/play/api/onAirNow/talksport');
        expect(request.url.queryParameters['refresh'], isNotEmpty);
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

  test('falls back to WebView now-playing after verification HTML', () async {
    SharedPreferences.setMockInitialValues({});
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'WebView show',
      nowPlayingTitle: 'WebView live show',
    );
    final api = TalkSportApi(
      client: MockClient((_) async => http.Response('<html></html>', 200)),
      pageScraper: scraper,
    );

    final nowPlaying = await api.fetchNowPlaying('talksport');

    expect(nowPlaying.title, 'WebView live show');
    expect(scraper.calls, 1);
  });

  test(
    'returns current-day cached schedule without blocking on refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(seconds: 10),
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
    'notifies listeners when background schedule metadata refreshes',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(minutes: 3),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
            scheduleDate: _todayKey(),
          ),
        ),
      });
      final scraper = _SuccessfulScraper(
        scheduleTitle: 'Fresh White & Jordan',
        nowPlayingTitle: 'Fresh live show',
      );
      final api = TalkSportApi(
        client: MockClient((_) async => throw StateError('HTTP was used')),
        pageScraper: scraper,
      );
      addTearDown(api.dispose);

      final update = api.scheduleUpdates.first;
      final schedule = await api.fetchSchedule('talksport');

      expect(schedule.single.shows.single.title, 'Cached White & Jordan');
      await expectLater(update, completion('talksport'));
      final refreshed = await api.fetchSchedule('talksport');
      expect(refreshed.single.shows.single.title, 'Fresh White & Jordan');
    },
  );

  test('keeps cached recording when fresh metadata omits it', () async {
    SharedPreferences.setMockInitialValues({
      'talksport.metadata.talksport': jsonEncode(
        _cachedPayloadJson(
          age: const Duration(minutes: 1),
          nowPlayingTitle: 'Cached live show',
          scheduleTitle: 'White & Jordan',
          scheduleDate: _todayKey(),
          withRecording: true,
        ),
      ),
    });
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'White & Jordan',
      nowPlayingTitle: 'Fresh live show',
    );
    final api = TalkSportApi(
      client: MockClient((_) async => throw StateError('HTTP was used')),
      pageScraper: scraper,
    );
    addTearDown(api.dispose);

    final schedule = await api.fetchSchedule('talksport', allowCached: false);

    expect(
      schedule.single.shows.single.recording?.url,
      'https://audio.test/show.mp3',
    );
  });

  test('forced refresh uses fresh scraper recordings', () async {
    SharedPreferences.setMockInitialValues({
      'talksport.metadata.talksport': jsonEncode(
        _cachedPayloadJson(
          age: const Duration(minutes: 1),
          nowPlayingTitle: 'Cached live show',
          scheduleTitle: 'White & Jordan',
          scheduleDate: _todayKey(),
        ),
      ),
    });
    final scraper = _SuccessfulScraper(
      scheduleTitle: 'White & Jordan',
      nowPlayingTitle: 'Fresh live show',
      withRecording: true,
    );
    final api = TalkSportApi(
      client: MockClient((_) async => throw StateError('HTTP was used')),
      pageScraper: scraper,
    );
    addTearDown(api.dispose);

    final schedule = await api.fetchSchedule('talksport', allowCached: false);

    expect(
      schedule.single.shows.single.recording?.url,
      'https://audio.test/show.mp3',
    );
    expect(scraper.forceRefreshes, [true]);
  });

  test(
    'forced refresh does not return stale schedule when scrape fails',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(minutes: 1),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
            scheduleDate: _todayKey(),
            withRecording: true,
          ),
        ),
      });
      final api = TalkSportApi(
        client: MockClient((_) async => throw StateError('HTTP was used')),
        pageScraper: _FailingScraper(),
      );
      addTearDown(api.dispose);

      await expectLater(
        api.fetchSchedule('talksport', allowCached: false),
        throwsA(isA<TalkSportApiException>()),
      );
    },
  );

  test('a timed-out scraper is reset before the next refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final scraper = _RecoveringScraper();
    final api = TalkSportApi(
      client: MockClient((_) async => http.Response('<html></html>', 200)),
      pageScraper: scraper,
      pageRequestTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(api.dispose);

    await expectLater(
      api.fetchSchedule('talksport', allowCached: false),
      throwsA(isA<TalkSportApiException>()),
    );

    final schedule = await api.fetchSchedule('talksport', allowCached: false);

    expect(scraper.resetCalls, 1);
    expect(scraper.calls, 2);
    expect(schedule.single.shows.single.title, 'Recovered White & Jordan');
  });

  test(
    'resume recovery resets the scraper and publishes fresh metadata',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(days: 1),
            nowPlayingTitle: 'Cached live show',
            scheduleTitle: 'Cached White & Jordan',
            scheduleDate: _todayKey(),
          ),
        ),
      });
      final scraper = _SuccessfulScraper(
        scheduleTitle: 'Resumed White & Jordan',
        nowPlayingTitle: 'Resumed live show',
      );
      final api = TalkSportApi(
        client: MockClient((_) async => http.Response('<html></html>', 200)),
        pageScraper: scraper,
      );
      addTearDown(api.dispose);

      final refreshComplete = api.scheduleUpdates.skip(1).first;
      await api.recoverAfterResume(['talksport']);
      final cachedSchedule = await api.fetchSchedule('talksport');
      expect(cachedSchedule.single.shows.single.title, 'Cached White & Jordan');
      await refreshComplete;
      final schedule = await api.fetchSchedule('talksport');

      expect(scraper.resetCalls, 1);
      expect(scraper.forceRefreshes, [true]);
      expect(schedule.single.shows.single.title, 'Resumed White & Jordan');
    },
  );

  test(
    'normalizes stale-date cached schedule instead of calling it today',
    () async {
      final cachedDate = DateTime.now().subtract(const Duration(days: 3));
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(seconds: 10),
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

  test(
    'returns fresh cached now-playing without blocking on refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'talksport.metadata.talksport': jsonEncode(
          _cachedPayloadJson(
            age: const Duration(seconds: 10),
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
  bool withRecording = false,
}) {
  final now = DateTime.now();
  return {
    'updatedAtMs': now.subtract(age).millisecondsSinceEpoch,
    'onAirNow': _nowPlaying(nowPlayingTitle).toJson(),
    'schedule': [
      _scheduleDay(
        scheduleTitle,
        date: scheduleDate,
        withRecording: withRecording,
      ).toJson(),
    ],
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

ScheduleDay _scheduleDay(
  String title, {
  String? date,
  bool withRecording = false,
}) {
  final dayDate = DateTime.tryParse(date ?? _todayKey()) ?? DateTime.now();
  return ScheduleDay(
    date: date ?? _todayKey(),
    itemId: 'today',
    dayNumber: 0,
    shows: [
      Show(
        id: 'show-1',
        title: title,
        programmeTitle: title,
        startTime: DateTime(dayDate.year, dayDate.month, dayDate.day, 10),
        endTime: DateTime(dayDate.year, dayDate.month, dayDate.day, 13),
        description: 'Cached show description.',
        images: const {},
        recording: withRecording
            ? const Recording(
                url: 'https://audio.test/show.mp3',
                duration: 10800000,
              )
            : null,
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

class _FailingScraper extends TalkSportPageScraper {
  int calls = 0;

  @override
  Future<TalkSportPagePayload> fetch(
    String stationSlug, {
    bool forceRefresh = false,
  }) async {
    calls++;
    throw StateError('Refresh failed');
  }
}

class _SuccessfulScraper extends TalkSportPageScraper {
  _SuccessfulScraper({
    required this.scheduleTitle,
    required this.nowPlayingTitle,
    this.withRecording = false,
  });

  final String scheduleTitle;
  final String nowPlayingTitle;
  final bool withRecording;
  int calls = 0;
  int resetCalls = 0;
  final List<bool> forceRefreshes = [];

  @override
  Future<void> reset() async {
    resetCalls++;
  }

  @override
  Future<TalkSportPagePayload> fetch(
    String stationSlug, {
    bool forceRefresh = false,
  }) async {
    calls++;
    forceRefreshes.add(forceRefresh);
    return TalkSportPagePayload(
      nowPlaying: _nowPlaying(nowPlayingTitle),
      schedule: [_scheduleDay(scheduleTitle, withRecording: withRecording)],
    );
  }
}

class _RecoveringScraper extends TalkSportPageScraper {
  int calls = 0;
  int resetCalls = 0;
  bool _recovered = false;

  @override
  Future<TalkSportPagePayload> fetch(
    String stationSlug, {
    bool forceRefresh = false,
  }) {
    calls++;
    if (!_recovered) {
      return Completer<TalkSportPagePayload>().future;
    }
    return Future.value(
      TalkSportPagePayload(
        nowPlaying: _nowPlaying('Recovered live show'),
        schedule: [_scheduleDay('Recovered White & Jordan')],
      ),
    );
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    _recovered = true;
  }
}
