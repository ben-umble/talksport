import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/models/now_playing.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';

void main() {
  test('parses talkSPORT schedule recordings', () {
    final decoded = jsonDecode(_scheduleJson) as List<dynamic>;
    final days = decoded
        .cast<Map<String, dynamic>>()
        .map(ScheduleDay.fromJson)
        .toList();

    expect(days, hasLength(2));
    expect(days.first.dayNumber, -1);
    expect(days.first.shows.first.title, 'White & Jordan');
    expect(days.first.shows.first.hasRecording, isTrue);
    expect(days.first.shows.first.recording?.durationValue.inHours, 3);
    expect(days.last.shows.first.hasRecording, isFalse);
  });

  test('parses now-playing response', () {
    final nowPlaying =
        NowPlaying.fromJson(jsonDecode(_nowPlayingJson) as Map<String, dynamic>);

    expect(nowPlaying.stationSlug, 'talksport');
    expect(nowPlaying.title, contains('GameDay'));
    expect(nowPlaying.nextShow?.title, 'White & Jordan');
    expect(nowPlaying.thumbnailUrl, endsWith('thumb.png'));
  });
}

const _scheduleJson = '''
[
  {
    "date": "2026-06-28",
    "dayNumber": -1,
    "itemId": "day-a",
    "shows": [
      {
        "id": "20260628-24974",
        "title": "White & Jordan",
        "programmeTitle": "White and Jordan",
        "startTime": "2026-06-28T12:00:00.000Z",
        "endTime": "2026-06-28T15:00:00.000Z",
        "description": "Jim White and Simon Jordan debate the big stories.",
        "images": {"thumbnail": "https://example.test/white.png"},
        "recording": {
          "url": "https://traffic.omny.fm/audio.mp3",
          "duration": 10800000
        },
        "liveVideo": {"url": null},
        "station_id": "talksport",
        "stationSlug": "talksport"
      }
    ]
  },
  {
    "date": "2026-06-29",
    "dayNumber": 0,
    "itemId": "day-b",
    "shows": [
      {
        "id": "20260629-1",
        "title": "Live Show",
        "programmeTitle": "Live",
        "startTime": "2026-06-29T15:00:00.000Z",
        "endTime": "2026-06-29T18:00:00.000Z",
        "description": "",
        "images": {},
        "recording": null,
        "liveVideo": {"url": null},
        "station_id": "talksport",
        "stationSlug": "talksport"
      }
    ]
  }
]
''';

const _nowPlayingJson = '''
{
  "title": "World Cup GameDay Live",
  "id": "20260629-25592",
  "description": "Live commentary.",
  "programmeTitle": "The Phone In",
  "images": {"thumbnail": "https://example.test/thumb.png"},
  "startTime": "2026-06-29T15:00:00.000Z",
  "endTime": "2026-06-29T19:30:00.000Z",
  "liveVideo": {"url": null},
  "hasLiveStream": false,
  "nextShow": {
    "id": "20260629-24974",
    "title": "White & Jordan",
    "programmeTitle": "White and Jordan",
    "startTime": "2026-06-29T12:00:00.000Z",
    "endTime": "2026-06-29T15:00:00.000Z",
    "description": "",
    "images": {},
    "liveVideo": {"url": null},
    "station_id": "talksport",
    "stationSlug": "talksport"
  },
  "stationSlug": "talksport",
  "station_id": "talksport",
  "type": "live"
}
''';
