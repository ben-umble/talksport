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

  test('removes cache files older than the retention period', () async {
    final now = DateTime.utc(2026, 7, 3, 12);
    final cache = CatchUpDownloadCache(rootDirectory: rootDirectory);
    addTearDown(cache.dispose);

    final expired = File(
      '${rootDirectory.path}${Platform.pathSeparator}old.mp3',
    )..writeAsBytesSync([1]);
    final expiredMarker = File('${expired.path}.complete')
      ..writeAsStringSync(
        now.subtract(const Duration(days: 8)).toIso8601String(),
      );

    final fresh = File(
      '${rootDirectory.path}${Platform.pathSeparator}fresh.mp3',
    )..writeAsBytesSync([2]);
    final freshMarker = File('${fresh.path}.complete')
      ..writeAsStringSync(
        now.subtract(const Duration(days: 6)).toIso8601String(),
      );

    final orphanMarker = File(
      '${rootDirectory.path}${Platform.pathSeparator}orphan.mp3.complete',
    )..writeAsStringSync(now.toIso8601String());
    final markerlessAudio = File(
      '${rootDirectory.path}${Platform.pathSeparator}markerless.mp3',
    )..writeAsBytesSync([3]);
    final leftoverPart = File(
      '${rootDirectory.path}${Platform.pathSeparator}download.mp3.part',
    )..writeAsBytesSync([4]);
    final oldOrphanModified = now.subtract(const Duration(hours: 2));
    await markerlessAudio.setLastModified(oldOrphanModified);
    await leftoverPart.setLastModified(oldOrphanModified);

    final deleted = await cache.cleanExpired(now: now);

    expect(deleted, 5);
    expect(await expired.exists(), isFalse);
    expect(await expiredMarker.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await freshMarker.exists(), isTrue);
    expect(await orphanMarker.exists(), isFalse);
    expect(await markerlessAudio.exists(), isFalse);
    expect(await leftoverPart.exists(), isFalse);
  });

  test('does not return expired cached audio', () async {
    final item = _catchUpItem();
    final expiredAt = DateTime.now().toUtc().subtract(
      CatchUpDownloadCache.defaultRetention + const Duration(days: 1),
    );
    final cache = CatchUpDownloadCache(rootDirectory: rootDirectory);
    addTearDown(cache.dispose);

    final file = await cache.fileFor(item);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    final marker = File('${file.path}.complete');
    await marker.writeAsString(expiredAt.toIso8601String());

    final cached = await cache.cachedFileFor(item);

    expect(cached, isNull);
    expect(await file.exists(), isFalse);
    expect(await marker.exists(), isFalse);
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
