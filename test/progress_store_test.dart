import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/data/progress_store.dart';
import 'package:talksport_companion/src/models/playback_item.dart';

void main() {
  test('stores last catch-up item and resume position', () async {
    final store = ProgressStore.memory();
    final item = PlaybackItem(
      id: 'white-and-jordan-20260629',
      kind: PlaybackKind.catchUp,
      stationSlug: 'talksport',
      stationName: 'talkSPORT',
      title: 'White & Jordan',
      subtitle: 'talkSPORT',
      description: 'Debate and big-name guests.',
      audioUrl: 'https://example.test/audio.mp3',
      imageUrl: 'https://example.test/art.png',
      duration: const Duration(hours: 3),
    );

    await store.saveProgress(item, const Duration(minutes: 42, seconds: 15));

    final progress = store.progressFor(item.id);
    expect(progress?.position, const Duration(minutes: 42, seconds: 15));
    expect(progress?.stationSlug, 'talksport');

    final lastItem = store.lastItem();
    expect(lastItem?.id, item.id);
    expect(lastItem?.title, 'White & Jordan');
    expect(lastItem?.isCatchUp, isTrue);
  });

  test('does not store progress for live streams', () async {
    final store = ProgressStore.memory();
    final item = PlaybackItem(
      id: 'live:talksport',
      kind: PlaybackKind.live,
      stationSlug: 'talksport',
      stationName: 'talkSPORT',
      title: 'Live show',
      subtitle: 'Live on talkSPORT',
      description: '',
      audioUrl: 'https://example.test/live',
      imageUrl: null,
      duration: null,
    );

    await store.saveProgress(item, const Duration(minutes: 5));

    expect(store.progressFor(item.id), isNull);
    expect(store.lastItem(), isNull);
  });
}
