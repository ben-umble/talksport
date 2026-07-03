import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/data/progress_store.dart';
import 'package:talksport_companion/src/models/playback_item.dart';
import 'package:talksport_companion/src/playback/talksport_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lazy restored catch-up items keep the current idle seek position',
    () async {
      final store = ProgressStore.memory();
      final item = PlaybackItem(
        id: '20260702-25052',
        kind: PlaybackKind.catchUp,
        stationSlug: 'talksport',
        stationName: 'talkSPORT',
        title: 'White & Jordan',
        subtitle: 'talkSPORT',
        description: '',
        audioUrl: 'https://example.test/audio.mp3',
        imageUrl: null,
        duration: const Duration(hours: 3),
        showDate: DateTime.utc(2026, 7, 2),
      );
      await store.saveProgress(item, const Duration(minutes: 14));
      expect(store.lastItem()?.id, item.id);
      expect(store.progressFor(item.id)?.position, const Duration(minutes: 14));
      final handler = TalkSportAudioHandler(
        store,
        null,
        configureSession: false,
      );
      addTearDown(handler.dispose);

      await handler.restoreLastItem();
      expect(handler.position, const Duration(minutes: 14));

      await handler.seek(const Duration(minutes: 19, seconds: 34));

      expect(handler.position, const Duration(minutes: 19, seconds: 34));
      expect(
        store.progressFor(item.id)?.position,
        const Duration(minutes: 19, seconds: 34),
      );
    },
  );
}
