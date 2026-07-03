import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talksport_companion/src/models/playback_item.dart';
import 'package:talksport_companion/src/playback/catch_up_download_cache.dart';

void main() {
  late Directory rootDirectory;

  setUp(() async {
    rootDirectory = await Directory.systemTemp.createTemp(
      'talksport-cache-test-',
    );
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  test('downloads catch-up audio once and reuses the cached file', () async {
    final item = _catchUpItem();
    final client = _StreamingAudioClient([1, 2, 3, 4]);
    final cache = CatchUpDownloadCache(
      rootDirectory: rootDirectory,
      client: client,
    );
    addTearDown(cache.dispose);

    final file = await cache.download(item);

    expect(file, isNotNull);
    expect(await file!.readAsBytes(), [1, 2, 3, 4]);
    expect(await File('${file.path}.part').exists(), isFalse);
    expect(await File('${file.path}.complete').exists(), isTrue);
    expect(client.requests, 1);
    expect(client.lastUrl, item.audioUrl);

    final cached = await cache.cachedFileFor(item);
    expect(cached?.path, file.path);

    final reused = await cache.download(item);
    expect(reused?.path, file.path);
    expect(client.requests, 1);
  });

  test('does not download live audio', () async {
    final client = _StreamingAudioClient([1]);
    final cache = CatchUpDownloadCache(
      rootDirectory: rootDirectory,
      client: client,
    );
    addTearDown(cache.dispose);

    final file = await cache.download(
      const PlaybackItem(
        id: 'live:talksport',
        kind: PlaybackKind.live,
        stationSlug: 'talksport',
        stationName: 'talkSPORT',
        title: 'Live',
        subtitle: 'talkSPORT',
        description: '',
        audioUrl: 'https://example.test/live.mp3',
        imageUrl: null,
        duration: null,
      ),
    );

    expect(file, isNull);
    expect(client.requests, 0);
    expect(await rootDirectory.list().isEmpty, isTrue);
  });
}

class _StreamingAudioClient extends http.BaseClient {
  _StreamingAudioClient(this.bytes);

  final List<int> bytes;
  int requests = 0;
  String? lastUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests += 1;
    lastUrl = request.url.toString();
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      headers: {'content-type': 'audio/mpeg'},
    );
  }
}

PlaybackItem _catchUpItem() {
  return PlaybackItem(
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
}
