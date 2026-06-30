import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/now_playing.dart';
import '../models/schedule_day.dart';
import 'talksport_page_scraper.dart';

class TalkSportMetadataCache {
  TalkSportMetadataCache([this._preferences]);

  static const _prefix = 'talksport.metadata.';

  SharedPreferences? _preferences;

  Future<CachedTalkSportPagePayload?> read(String stationSlug) async {
    final raw = (await _prefs()).getString('$_prefix$stationSlug');
    if (raw == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final updatedAtMs = decoded['updatedAtMs'] as int? ?? 0;
      final onAirNow = decoded['onAirNow'];
      final schedule = decoded['schedule'];
      if (onAirNow is! Map<String, dynamic> || schedule is! List) {
        return null;
      }

      final days = schedule
          .whereType<Map<String, dynamic>>()
          .map(ScheduleDay.fromJson)
          .toList()
        ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
      if (days.isEmpty) {
        return null;
      }

      return CachedTalkSportPagePayload(
        payload: TalkSportPagePayload(
          nowPlaying: NowPlaying.fromJson(onAirNow),
          schedule: days,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String stationSlug, TalkSportPagePayload payload) async {
    final encoded = jsonEncode({
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'onAirNow': payload.nowPlaying.toJson(),
      'schedule': payload.schedule.map((day) => day.toJson()).toList(),
    });
    await (await _prefs()).setString('$_prefix$stationSlug', encoded);
  }

  Future<SharedPreferences> _prefs() async {
    final existing = _preferences;
    if (existing != null) {
      return existing;
    }
    return _preferences = await SharedPreferences.getInstance();
  }
}

class CachedTalkSportPagePayload {
  const CachedTalkSportPagePayload({
    required this.payload,
    required this.updatedAt,
  });

  final TalkSportPagePayload payload;
  final DateTime updatedAt;

  Duration get age => DateTime.now().difference(updatedAt);
}
