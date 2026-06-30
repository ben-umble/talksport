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
  }) : _client = client ?? http.Client(),
       _pageScraper = pageScraper ?? TalkSportPageScraper.maybeCreate(),
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

  Future<List<ScheduleDay>> fetchSchedule(
    String stationSlug, {
    bool allowCached = true,
  }) async {
    final cache = _scheduleCache[stationSlug];
    if (allowCached) {
      final cached = await _cachedPagePayload(stationSlug);
      if (cached != null) {
        _refreshMetadataInBackground(stationSlug, cached);
        return cached.payload.schedule;
      }
    }

    final pagePayload = await _fetchPagePayload(stationSlug);
    if (pagePayload != null) {
      _scheduleCache[stationSlug] = _ScheduleCacheEntry(pagePayload.schedule);
      unawaited(_metadataCache.write(stationSlug, pagePayload));
      return pagePayload.schedule;
    }

    try {
      final decoded =
          await _getJson(
                Uri.parse('$_baseUrl/schedule/$stationSlug'),
                'Schedule',
              )
              as List<dynamic>;
      final days =
          decoded
              .whereType<Map<String, dynamic>>()
              .map(ScheduleDay.fromJson)
              .toList()
            ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
      _scheduleCache[stationSlug] = _ScheduleCacheEntry(days);
      return days;
    } catch (error, stackTrace) {
      if (cache != null) {
        return cache.days;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<NowPlaying> fetchNowPlaying(String stationSlug) async {
    final cached = await _cachedPagePayload(stationSlug);
    if (cached != null) {
      _refreshMetadataInBackground(stationSlug, cached);
      return cached.payload.nowPlaying;
    }

    final pagePayload = await _fetchPagePayload(stationSlug);
    if (pagePayload != null) {
      unawaited(_metadataCache.write(stationSlug, pagePayload));
      return pagePayload.nowPlaying;
    }

    try {
      final decoded =
          await _getJson(
                Uri.parse('$_baseUrl/onAirNow/$stationSlug'),
                'Now playing',
              )
              as Map<String, dynamic>;
      return NowPlaying.fromJson(decoded);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Object?> _getJson(Uri uri, String label) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TalkSportApiException(
        '$label request failed with ${response.statusCode}.',
      );
    }
    return _decodeJson(response);
  }

  Future<TalkSportPagePayload?> _fetchPagePayload(String stationSlug) async {
    final pageScraper = _pageScraper;
    if (pageScraper == null) {
      return null;
    }
    try {
      final payload = await _pagePayloadWithTimeout(
        pageScraper.fetch(stationSlug),
        const Duration(seconds: 45),
      );
      if (payload != null) {
        return payload;
      }

      return _pagePayloadWithTimeout(
        pageScraper.fetch(stationSlug),
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

    _backgroundRefreshes[stationSlug] = _fetchPagePayload(stationSlug)
        .then((payload) async {
          if (payload != null) {
            await _metadataCache.write(stationSlug, payload);
            _scheduleCache[stationSlug] = _ScheduleCacheEntry(payload.schedule);
          }
        })
        .catchError((_) {})
        .whenComplete(() => _backgroundRefreshes.remove(stationSlug));
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
