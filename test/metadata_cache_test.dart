import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talksport_companion/src/data/talksport_metadata_cache.dart';
import 'package:talksport_companion/src/data/talksport_page_scraper.dart';
import 'package:talksport_companion/src/models/now_playing.dart';
import 'package:talksport_companion/src/models/schedule_day.dart';
import 'package:talksport_companion/src/models/show.dart';

void main() {
  test('persists and restores talkSPORT metadata payloads', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = TalkSportMetadataCache();
    final payload = TalkSportPagePayload(
      nowPlaying: NowPlaying(
        title: 'White & Jordan',
        id: 'live',
        description: 'Live debate.',
        programmeTitle: 'White and Jordan',
        images: const {},
        startTime: DateTime.utc(2026, 6, 30, 10),
        endTime: DateTime.utc(2026, 6, 30, 13),
        liveVideo: const {},
        hasLiveStream: false,
        nextShow: null,
        stationSlug: 'talksport',
        stationId: 'talksport',
        type: 'live',
      ),
      schedule: [
        ScheduleDay(
          date: '2026-06-30',
          shows: [
            Show(
              id: 'show-1',
              title: 'White & Jordan',
              programmeTitle: 'White and Jordan',
              startTime: DateTime.utc(2026, 6, 30, 10),
              endTime: DateTime.utc(2026, 6, 30, 13),
              description: 'A test show.',
              images: const {},
              recording: null,
              liveVideo: const {},
              stationId: 'talksport',
              stationSlug: 'talksport',
            ),
          ],
          itemId: 'today',
          dayNumber: 0,
        ),
      ],
    );

    await cache.write('talksport', payload);

    final restored = await cache.read('talksport');
    expect(restored, isNotNull);
    expect(restored!.payload.nowPlaying.title, 'White & Jordan');
    expect(restored.payload.schedule.single.shows.single.id, 'show-1');
    expect(restored.age, lessThan(const Duration(seconds: 5)));
  });
}
