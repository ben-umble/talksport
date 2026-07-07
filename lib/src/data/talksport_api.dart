import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/now_playing.dart';
import '../models/schedule_day.dart';
import '../models/show.dart';
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
  final StreamController<String> _scheduleUpdates =
      StreamController<String>.broadcast();

  static const _cachedMetadataMaxAge = Duration(days: 7);
  static const _backgroundRefreshAfter = Duration(minutes: 2);
  static const _availabilityRefreshAfter = Duration(seconds: 30);
  static const _requestTimeout = Duration(seconds: 8);

  Stream<String> get scheduleUpdates => _scheduleUpdates.stream;

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
      final stabilizedPayload = await _stabilizePayload(
        stationSlug,
        pagePayload,
      );
      _scheduleCache[stationSlug] = _ScheduleCacheEntry(
        stabilizedPayload.schedule,
      );
      unawaited(_metadataCache.write(stationSlug, stabilizedPayload));
      return stabilizedPayload.schedule;
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
      final stabilizedPayload = await _stabilizePayload(
        stationSlug,
        pagePayload,
      );
      unawaited(_metadataCache.write(stationSlug, stabilizedPayload));
      return stabilizedPayload.nowPlaying;
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
    final refreshAfter = _needsAvailabilityProbe(cached.payload.schedule)
        ? _availabilityRefreshAfter
        : _backgroundRefreshAfter;
    if (cached.age < refreshAfter ||
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
            final stabilizedPayload = await _stabilizePayload(
              stationSlug,
              payload,
            );
            await _metadataCache.write(stationSlug, stabilizedPayload);
            _scheduleCache[stationSlug] = _ScheduleCacheEntry(
              stabilizedPayload.schedule,
            );
            _notifyScheduleUpdated(stationSlug);
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

  Future<TalkSportPagePayload> _stabilizePayload(
    String stationSlug,
    TalkSportPagePayload freshPayload,
  ) async {
    final cachedPayload = await _cachedPagePayload(stationSlug);
    if (cachedPayload == null) {
      return freshPayload;
    }

    return TalkSportPagePayload(
      nowPlaying: freshPayload.nowPlaying,
      schedule: _mergeKnownRecordings(
        freshPayload.schedule,
        cachedPayload.payload.schedule,
      ),
    );
  }

  List<ScheduleDay> _mergeKnownRecordings(
    List<ScheduleDay> freshDays,
    List<ScheduleDay> cachedDays,
  ) {
    return [
      for (final freshDay in freshDays)
        ScheduleDay(
          date: freshDay.date,
          shows: [
            for (final freshShow in freshDay.shows)
              _showWithKnownRecording(
                freshShow,
                _findCachedShow(freshShow, cachedDays),
              ),
          ],
          itemId: freshDay.itemId,
          dayNumber: freshDay.dayNumber,
        ),
    ];
  }

  Show _showWithKnownRecording(Show freshShow, Show? cachedShow) {
    if (freshShow.hasRecording ||
        cachedShow == null ||
        !cachedShow.hasRecording) {
      return freshShow;
    }

    return Show(
      id: freshShow.id,
      title: freshShow.title,
      programmeTitle: freshShow.programmeTitle,
      startTime: freshShow.startTime,
      endTime: freshShow.endTime,
      description: freshShow.description,
      images: freshShow.images,
      recording: cachedShow.recording,
      liveVideo: freshShow.liveVideo,
      stationId: freshShow.stationId,
      stationSlug: freshShow.stationSlug,
    );
  }

  Show? _findCachedShow(Show freshShow, List<ScheduleDay> cachedDays) {
    for (final cachedDay in cachedDays) {
      for (final cachedShow in cachedDay.shows) {
        if (_isSameShow(freshShow, cachedShow)) {
          return cachedShow;
        }
      }
    }
    return null;
  }

  bool _isSameShow(Show a, Show b) {
    if (a.id.isNotEmpty && a.id == b.id) {
      return true;
    }
    return a.title == b.title &&
        a.startTime == b.startTime &&
        a.endTime == b.endTime;
  }

  bool _needsAvailabilityProbe(List<ScheduleDay> schedule) {
    final displaySchedule = _scheduleForDisplay(schedule);
    if (displaySchedule == null) {
      return false;
    }
    ScheduleDay? today;
    for (final day in displaySchedule) {
      if (day.dayNumber == 0) {
        today = day;
        break;
      }
    }
    if (today == null) {
      return false;
    }

    final now = DateTime.now();
    final completedShows = today.shows.where((show) {
      final endedAt = show.endTime.toLocal();
      return now.difference(endedAt) > const Duration(minutes: 20);
    }).toList();
    if (completedShows.isEmpty) {
      return false;
    }

    return completedShows.any((show) => !show.hasRecording);
  }

  void _notifyScheduleUpdated(String stationSlug) {
    if (!_scheduleUpdates.isClosed) {
      _scheduleUpdates.add(stationSlug);
    }
  }

  void dispose() {
    unawaited(_scheduleUpdates.close());
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
