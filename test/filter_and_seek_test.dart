import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/models/recording.dart';
import 'package:talksport_companion/src/models/show.dart';
import 'package:talksport_companion/src/util/playback_math.dart';
import 'package:talksport_companion/src/util/show_filters.dart';
import 'package:talksport_companion/src/util/timecode.dart';

void main() {
  test('filters shows by title, programme, and description', () {
    final shows = [
      _show(title: 'White & Jordan', programmeTitle: 'Midday'),
      _show(title: 'Breakfast', description: 'Premier League reaction'),
    ];

    expect(filterShows(shows, 'jordan'), [shows.first]);
    expect(filterShows(shows, 'league'), [shows.last]);
    expect(filterShows(shows, ''), shows);
  });

  test('finds playable catch-up shows', () {
    final playable = _show(title: 'Playable', withRecording: true);
    final unavailable = _show(title: 'Unavailable', withRecording: false);

    expect(playableShows([playable, unavailable]), [playable]);
  });

  test('clamps 15-second skips at start and end', () {
    expect(
      clampSeekPosition(
        current: const Duration(seconds: 10),
        delta: const Duration(seconds: -15),
      ),
      Duration.zero,
    );
    expect(
      clampSeekPosition(
        current: const Duration(seconds: 55),
        delta: const Duration(seconds: 15),
        duration: const Duration(minutes: 1),
      ),
      const Duration(minutes: 1),
    );
    expect(
      clampSeekPosition(
        current: const Duration(seconds: 30),
        delta: const Duration(seconds: 15),
        duration: const Duration(minutes: 1),
      ),
      const Duration(seconds: 45),
    );
  });

  test('parses typed time jumps', () {
    expect(parseTimecode('75'), const Duration(seconds: 75));
    expect(parseTimecode('12:34'), const Duration(minutes: 12, seconds: 34));
    expect(
      parseTimecode('1:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(
      parseTimecode('2:00:00', max: const Duration(hours: 1)),
      const Duration(hours: 1),
    );
    expect(parseTimecode('nope'), isNull);
  });
}

Show _show({
  required String title,
  String programmeTitle = '',
  String description = '',
  bool withRecording = true,
}) {
  return Show(
    id: title,
    title: title,
    programmeTitle: programmeTitle,
    startTime: DateTime.utc(2026, 6, 29, 12),
    endTime: DateTime.utc(2026, 6, 29, 15),
    description: description,
    images: const {},
    recording: withRecording
        ? const Recording(url: 'https://example.test/audio.mp3', duration: 1)
        : null,
    liveVideo: const {},
    stationId: 'talksport',
    stationSlug: 'talksport',
  );
}
