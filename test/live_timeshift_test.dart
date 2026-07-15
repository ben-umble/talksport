import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:talksport_companion/src/playback/live_audio_frame_parser.dart';
import 'package:talksport_companion/src/playback/live_timeshift_session.dart';
import 'package:talksport_companion/src/playback/live_timeshift_state.dart';

void main() {
  test('MP3 frame parser survives split chunks and leading noise', () {
    final parser = LiveAudioFrameParser(LiveAudioFormat.mp3);
    final stream = Uint8List.fromList([
      1,
      2,
      3,
      ..._mp3Frame(11),
      ..._mp3Frame(22),
      ..._mp3Frame(33),
    ]);

    final first = parser.add(stream.sublist(0, 300));
    final second = parser.add(stream.sublist(300));
    final frames = [...first, ...second];

    expect(frames, hasLength(2));
    expect(frames.every((frame) => frame.bytes.length == 208), isTrue);
    expect(frames.first.sampleRate, 44100);
    expect(frames.first.sampleCount, 1152);
    expect(frames[1].bytes[8], 22);
  });

  test('AAC ADTS frame parser indexes complete frames', () {
    final parser = LiveAudioFrameParser(LiveAudioFormat.aacAdts);
    final frames = parser.add([
      ..._aacFrame(100, 44),
      ..._aacFrame(100, 55),
      ..._aacFrame(100, 66),
    ]);

    expect(frames, hasLength(2));
    expect(frames.first.bytes.length, 100);
    expect(frames.first.sampleRate, 44100);
    expect(frames.first.sampleCount, 1024);
    expect(frames.last.bytes[10], 55);
  });

  test('live state reports delay and seek availability', () {
    const state = LiveTimeshiftState(
      phase: LiveTimeshiftPhase.ready,
      bufferStart: Duration(minutes: 1),
      liveEdge: Duration(minutes: 12),
      playbackPosition: Duration(minutes: 10, seconds: 30),
    );

    expect(state.bufferedDuration, const Duration(minutes: 11));
    expect(state.behindLive, const Duration(minutes: 1, seconds: 30));
    expect(state.canSeek, isTrue);
    expect(state.canGoLive, isTrue);
    expect(state.isAtLiveEdge, isFalse);
  });

  test('presentation clock smooths packet-based live edge updates', () {
    final clock = LiveEdgePresentationClock();
    final startedAt = DateTime.utc(2026, 7, 15, 12);

    final first = clock.project(
      observedEdge: const Duration(seconds: 20),
      observedAt: startedAt,
      phase: LiveTimeshiftPhase.ready,
      at: startedAt,
    );
    final betweenPackets = clock.project(
      observedEdge: const Duration(seconds: 20),
      observedAt: startedAt,
      phase: LiveTimeshiftPhase.ready,
      at: startedAt.add(const Duration(milliseconds: 900)),
    );
    final jitteredPacket = clock.project(
      observedEdge: const Duration(seconds: 21, milliseconds: 400),
      observedAt: startedAt.add(const Duration(seconds: 1)),
      phase: LiveTimeshiftPhase.ready,
      at: startedAt.add(const Duration(seconds: 1)),
    );

    expect(first, const Duration(seconds: 20));
    expect(betweenPackets, const Duration(seconds: 20, milliseconds: 900));
    expect(jitteredPacket, const Duration(seconds: 21, milliseconds: 25));
  });

  test('presentation clock freezes when live observations go stale', () {
    final clock = LiveEdgePresentationClock(
      maximumExtrapolation: const Duration(seconds: 2),
    );
    final startedAt = DateTime.utc(2026, 7, 15, 12);
    clock.project(
      observedEdge: const Duration(seconds: 20),
      observedAt: startedAt,
      phase: LiveTimeshiftPhase.ready,
      at: startedAt,
    );
    final atLimit = clock.project(
      observedEdge: const Duration(seconds: 20),
      observedAt: startedAt,
      phase: LiveTimeshiftPhase.ready,
      at: startedAt.add(const Duration(seconds: 2)),
    );
    final stale = clock.project(
      observedEdge: const Duration(seconds: 20),
      observedAt: startedAt,
      phase: LiveTimeshiftPhase.ready,
      at: startedAt.add(const Duration(seconds: 3)),
    );
    final stillStale = clock.project(
      observedEdge: const Duration(seconds: 20),
      observedAt: startedAt,
      phase: LiveTimeshiftPhase.ready,
      at: startedAt.add(const Duration(seconds: 4)),
    );

    expect(atLimit, const Duration(seconds: 22));
    expect(stale, const Duration(seconds: 22, milliseconds: 750));
    expect(stillStale, stale);
  });

  test(
    'disk relay keeps recording while its playback client is paused',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'talksport-live-test-',
      );
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestTasks = <Future<void>>[];
      upstream.listen((request) {
        requestTasks.add(_serveMp3Frames(request));
      });
      addTearDown(() async {
        try {
          await upstream.close(force: true).timeout(const Duration(seconds: 1));
          await Future.wait(
            requestTasks.map((task) => task.catchError((_) {})),
          ).timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // The synthetic source may still be unwinding a forced socket close.
        }
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final manager = LiveTimeshiftManager(
        rootDirectory: root,
        initialBuffer: const Duration(milliseconds: 100),
        segmentDuration: const Duration(milliseconds: 160),
        maximumBuffer: const Duration(milliseconds: 650),
        startupTimeout: const Duration(seconds: 3),
      );
      final session = await manager.start(
        sourceUri: Uri.parse(
          'http://${upstream.address.address}:${upstream.port}/live',
        ),
        stationSlug: 'talksport',
      );
      addTearDown(() async {
        await session.stop().timeout(const Duration(seconds: 5));
      });

      await _waitUntil(
        () => session.state.value.liveEdge >= const Duration(milliseconds: 400),
      );
      final endpoint = session.endpointAt(
        session.liveEdge - const Duration(milliseconds: 150),
      );
      final client = HttpClient();
      addTearDown(() {
        client.close(force: true);
      });
      final request = await client.getUrl(endpoint.uri);
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      final received = <int>[];
      final firstBytes = Completer<void>();
      final crossedSeveralSegments = Completer<void>();
      var resumed = false;
      late final StreamSubscription<List<int>> subscription;
      subscription = response.listen((chunk) {
        received.addAll(chunk);
        if (received.length >= 416 && !firstBytes.isCompleted) {
          firstBytes.complete();
          subscription.pause();
        }
        if (resumed &&
            received.length >= 2496 &&
            !crossedSeveralSegments.isCompleted) {
          crossedSeveralSegments.complete();
        }
      });
      await firstBytes.future.timeout(const Duration(seconds: 2));
      expect(received[0], 0xff);
      expect(received[1], 0xfb);

      final edgeWhenPaused = session.state.value.liveEdge;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await _waitUntil(() => session.state.value.liveEdge > edgeWhenPaused);
      expect(session.state.value.bufferStart, greaterThan(Duration.zero));
      resumed = true;
      subscription.resume();
      await crossedSeveralSegments.future.timeout(const Duration(seconds: 2));
      expect(received.length, greaterThanOrEqualTo(2496));
      await subscription.cancel().timeout(const Duration(seconds: 2));
    },
  );
}

Future<void> _serveMp3Frames(HttpRequest request) async {
  request.response.headers.contentType = ContentType('audio', 'mpeg');
  try {
    for (var index = 0; index < 2000; index += 1) {
      request.response.add(_mp3Frame(index & 0xff));
      if (index % 4 == 0) {
        await request.response.flush();
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await request.response.close();
  } catch (_) {
    // The test closes the source once the relay behavior has been verified.
  }
}

Uint8List _mp3Frame(int fill) {
  final bytes = Uint8List(208)..fillRange(4, 208, fill);
  bytes.setRange(0, 4, const [0xff, 0xfb, 0x50, 0xc0]);
  return bytes;
}

Uint8List _aacFrame(int length, int fill) {
  final bytes = Uint8List(length)..fillRange(7, length, fill);
  bytes[0] = 0xff;
  bytes[1] = 0xf1;
  bytes[2] = 0x50;
  bytes[3] = 0x80 | ((length >> 11) & 0x03);
  bytes[4] = (length >> 3) & 0xff;
  bytes[5] = ((length & 0x07) << 5) | 0x1f;
  bytes[6] = 0xfc;
  return bytes;
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached before the deadline.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
