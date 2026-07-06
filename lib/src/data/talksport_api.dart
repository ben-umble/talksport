import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/now_playing.dart';
import '../models/schedule_day.dart';
import 'talksport_metadata_cache.dart';
import 'talksport_page_scraper.dart';

class TalkSportApi {
  TalkSportApi({
    http.Client? client,
    TalkSportPageScraper? pageScraper,
    TalkSportMetadataCache? metadataCache,
    bool createDefaultPageScraper = true,
  }) : _client = client ?? http.Client(),
       _pageScraper =
           pageScraper ??
           (createDefaultPageScraper
               ? TalkSportPageScraper.maybeCreate()
               : null),
       _metadataCache = metadataCache ?? TalkSportMetadataCache();

  static const _baseUrl = 'https://talksport.com/play/api';
  static const _headers = {
    'accept': 'application/json,text/plain,*/*',
    'accept-language': 'en-GB,en;q=0.9',
    'cookie': 'country_code_test=GB',
    'referer': 'https://talksport.com/play/talksport',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-origin',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
  };

  final http.Client _client;
  final TalkSportPageScraper? _pageScraper;
  final TalkSportMetadataCache _metadataCache;
  final Map<String, _ScheduleCacheEntry> _scheduleCache = {};
  final Map<String, Future<void>> _backgroundRefreshes = {};

  static const _cachedMetadataMaxAge = Duration(days: 7);
  static const _backgroundRefreshAfter = Duration(minutes: 2);
  static const _requestTimeout = Duration(seconds: 8);

  Future<List<ScheduleDay>> fetchSchedule(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    final cache = _scheduleCache[stationSlug];
    CachedTalkSportPagePayload? cached;
    if (allowCached) {
      cached = await _cachedPagePayload(stationSlug);
      if (cached != null) {
        final cachedSchedule = _scheduleForDisplay(cached.payload.schedule);
        if (cachedSchedule != null) {
          _scheduleCache[stationSlug] = _ScheduleCacheEntry(cachedSchedule);
          _refreshMetadataInBackground(stationSlug, cached);
          return cachedSchedule;
        }
      }
    }

    final pagePayload = await _fetchPagePayload(
      stationSlug,
      forceRefresh: !allowCached,
    );
    if (pagePayload != null) {
      _scheduleCache[stationSlug] = _ScheduleCacheEntry(pagePayload.schedule);
      unawaited(_metadataCache.write(stationSlug, pagePayload));
      return pagePayload.schedule;
    }

    final days = await _fetchScheduleFromApi(stationSlug);
    if (days != null) {
      _scheduleCache[stationSlug] = _ScheduleCacheEntry(days);
      _refreshApiMetadataInBackground(stationSlug);
      return days;
    }

    final displayCache = _scheduleForDisplay(cache?.days);
    if (displayCache != null) {
      return displayCache;
    }
    throw const TalkSportApiException('Schedule is unavailable.');
  }

  Future<NowPlaying> fetchNowPlaying(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    if (allowCached) {
      final cached = await _cachedPagePayload(stationSlug);
      if (cached != null && cached.age < _backgroundRefreshAfter) {
        _refreshMetadataInBackground(stationSlug, cached);
        return cached.payload.nowPlaying;
      }
    }

    final pagePayload = await _fetchPagePayload(
      stationSlug,
      forceRefresh: !allowCached,
    );
    if (pagePayload != null) {
      unawaited(_metadataCache.write(stationSlug, pagePayload));
      return pagePayload.nowPlaying;
    }

    final nowPlaying = await _fetchNowPlayingFromApi(stationSlug);
    if (nowPlaying != null) {
      _refreshApiMetadataInBackground(stationSlug);
      return nowPlaying;
    }

    throw const TalkSportApiException('Now playing is unavailable.');
  }

  Future<TalkSportPagePayload?> _fetchApiPayload(String stationSlug) async {
    if (!_canUseDirectApi) {
      return null;
    }

    try {
      final results = await Future.wait<Object?>([
        _getJson(Uri.parse('$_baseUrl/schedule/$stationSlug'), 'Schedule'),
        _getJson(Uri.parse('$_baseUrl/onAirNow/$stationSlug'), 'Now playing'),
      ]);
      final schedule = _scheduleFromDecoded(results[0] as List<dynamic>);
      final nowPlaying = NowPlaying.fromJson(
        results[1] as Map<String, dynamic>,
      );
      return TalkSportPagePayload(nowPlaying: nowPlaying, schedule: schedule);
    } catch (_) {
      return null;
    }
  }

  Future<List<ScheduleDay>?> _fetchScheduleFromApi(String stationSlug) async {
    if (!_canUseDirectApi) {
      return null;
    }

    try {
      final decoded =
          await _getJson(
                Uri.parse('$_baseUrl/schedule/$stationSlug'),
                'Schedule',
              )
              as List<dynamic>;
      return _scheduleFromDecoded(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<NowPlaying?> _fetchNowPlayingFromApi(String stationSlug) async {
    if (!_canUseDirectApi) {
      return null;
    }

    try {
      final decoded =
          await _getJson(
                Uri.parse('$_baseUrl/onAirNow/$stationSlug'),
                'Now playing',
              )
              as Map<String, dynamic>;
      return NowPlaying.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _getJson(Uri uri, String label) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TalkSportApiException(
        '$label request failed with ${response.statusCode}.',
      );
    }
    return _decodeJson(response);
  }

  Future<TalkSportPagePayload?> _fetchPagePayload(
    String stationSlug, {
    bool forceRefresh = false,
  }) async {
    final pageScraper = _pageScraper;
    if (pageScraper == null) {
      return null;
    }
    try {
      final payload = await _pagePayloadWithTimeout(
        pageScraper.fetch(stationSlug, forceRefresh: forceRefresh),
        const Duration(seconds: 15),
      );
      if (payload != null) {
        return payload;
      }

      return _pagePayloadWithTimeout(
        pageScraper.fetch(stationSlug, forceRefresh: forceRefresh),
        const Duration(seconds: 3),
      );
    } catch (_) {
      return null;
    }
  }

  Future<CachedTalkSportPagePayload?> _cachedPagePayload(
    String stationSlug,
  ) async {
    final cached = await _metadataCache.read(stationSlug);
    if (cached == null || cached.age > _cachedMetadataMaxAge) {
      return null;
    }
    return cached;
  }

  void _refreshMetadataInBackground(
    String stationSlug,
    CachedTalkSportPagePayload cached,
  ) {
    if (cached.age < _backgroundRefreshAfter ||
        _backgroundRefreshes.containsKey(stationSlug)) {
      return;
    }

    _refreshApiMetadataInBackground(stationSlug);
  }

  void _refreshApiMetadataInBackground(String stationSlug) {
    if (_backgroundRefreshes.containsKey(stationSlug)) {
      return;
    }

    _backgroundRefreshes[stationSlug] = _fetchBestMetadataPayload(stationSlug)
        .then((payload) async {
          if (payload != null) {
            await _metadataCache.write(stationSlug, payload);
            _scheduleCache[stationSlug] = _ScheduleCacheEntry(payload.schedule);
          }
        })
        .catchError((_) {})
        .whenComplete(() => _backgroundRefreshes.remove(stationSlug));
  }

  Future<TalkSportPagePayload?> _fetchBestMetadataPayload(
    String stationSlug,
  ) async {
    return await _fetchPagePayload(stationSlug, forceRefresh: true) ??
        await _fetchApiPayload(stationSlug);
  }

  Future<TalkSportPagePayload?> _pagePayloadWithTimeout(
    Future<TalkSportPagePayload> payload,
    Duration timeout,
  ) async {
    try {
      return await payload.timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  Object? _decodeJson(http.Response response) {
    final body = response.body.trimLeft();
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/html') ||
        body.startsWith('<!DOCTYPE') ||
        body.startsWith('<html')) {
      throw const TalkSportApiException(
        'talkSPORT returned a verification page instead of JSON.',
      );
    }
    return jsonDecode(response.body);
  }

  List<ScheduleDay> _scheduleFromDecoded(List<dynamic> decoded) {
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ScheduleDay.fromJson)
        .toList()
      ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  }

  List<ScheduleDay>? _scheduleForDisplay(List<ScheduleDay>? schedule) {
    if (schedule == null || schedule.isEmpty) {
      return null;
    }

    final today = _localDate(DateTime.now());
    final normalized = <ScheduleDay>[];
    for (final day in schedule) {
      final date = _scheduleDayDate(day);
      if (date == null) {
        normalized.add(day);
        continue;
      }
      final localDate = _localDate(date);
      normalized.add(
        ScheduleDay(
          date: day.date,
          shows: day.shows,
          itemId: day.itemId,
          dayNumber: localDate.difference(today).inDays,
        ),
      );
    }

    final hasRelevantDay = normalized.any(
      (day) => day.dayNumber >= -7 && day.dayNumber <= 0,
    );
    if (!hasRelevantDay) {
      return null;
    }

    return normalized..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  }

  DateTime? _scheduleDayDate(ScheduleDay day) {
    final parsed = DateTime.tryParse(day.date);
    if (parsed != null) {
      return parsed;
    }
    if (day.shows.isNotEmpty) {
      return day.shows.first.startTime;
    }
    return null;
  }

  bool get _canUseDirectApi {
    return _pageScraper == null;
  }

  DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

class TalkSportApiException implements Exception {
  const TalkSportApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ScheduleCacheEntry {
  const _ScheduleCacheEntry(this.days);

  final List<ScheduleDay> days;
}
