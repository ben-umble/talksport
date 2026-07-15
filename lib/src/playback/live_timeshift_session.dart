import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'live_audio_frame_parser.dart';
import 'live_timeshift_state.dart';

@immutable
class LiveBufferSnapshot {
  const LiveBufferSnapshot({
    required this.phase,
    required this.bufferStart,
    required this.liveEdge,
    this.observedAt,
    this.errorMessage,
  });

  const LiveBufferSnapshot.idle()
    : phase = LiveTimeshiftPhase.idle,
      bufferStart = Duration.zero,
      liveEdge = Duration.zero,
      observedAt = null,
      errorMessage = null;

  final LiveTimeshiftPhase phase;
  final Duration bufferStart;
  final Duration liveEdge;
  final DateTime? observedAt;
  final String? errorMessage;
}

@immutable
class LivePlaybackEndpoint {
  const LivePlaybackEndpoint({required this.uri, required this.position});

  final Uri uri;
  final Duration position;
}

class LiveTimeshiftManager {
  LiveTimeshiftManager({
    required this.rootDirectory,
    this.maximumBuffer = const Duration(hours: 4),
    this.segmentDuration = const Duration(seconds: 30),
    this.initialBuffer = const Duration(milliseconds: 1500),
    this.startupTimeout = const Duration(seconds: 15),
  });

  final Directory rootDirectory;
  final Duration maximumBuffer;
  final Duration segmentDuration;
  final Duration initialBuffer;
  final Duration startupTimeout;
  Future<void>? _cleanupTask;

  static Future<Directory> defaultRootDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(
      '${temporary.path}${Platform.pathSeparator}talksport_companion'
      '${Platform.pathSeparator}live_timeshift',
    );
  }

  Future<void> cleanStaleSessions() {
    return _cleanupTask ??= _cleanStaleSessions();
  }

  Future<void> _cleanStaleSessions() async {
    if (!await rootDirectory.exists()) {
      return;
    }
    await for (final entity in rootDirectory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (error) {
        debugPrint('Could not remove stale live buffer ${entity.path}: $error');
      }
    }
  }

  Future<LiveTimeshiftSession> start({
    required Uri sourceUri,
    required String stationSlug,
  }) async {
    await cleanStaleSessions();
    await rootDirectory.create(recursive: true);
    final sessionDirectory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
    );
    final session = LiveTimeshiftSession._(
      sourceUri: sourceUri,
      stationSlug: stationSlug,
      directory: sessionDirectory,
      format: stationSlug == 'talksport2'
          ? LiveAudioFormat.aacAdts
          : LiveAudioFormat.mp3,
      maximumBuffer: maximumBuffer,
      segmentDuration: segmentDuration,
      initialBuffer: initialBuffer,
      startupTimeout: startupTimeout,
    );
    await session.start();
    return session;
  }
}

class LiveTimeshiftSession {
  LiveTimeshiftSession._({
    required this.sourceUri,
    required this.stationSlug,
    required this.directory,
    required this.format,
    required this.maximumBuffer,
    required this.segmentDuration,
    required this.initialBuffer,
    required this.startupTimeout,
  });

  final Uri sourceUri;
  final String stationSlug;
  final Directory directory;
  final LiveAudioFormat format;
  final Duration maximumBuffer;
  final Duration segmentDuration;
  final Duration initialBuffer;
  final Duration startupTimeout;
  final ValueNotifier<LiveBufferSnapshot> state = ValueNotifier(
    const LiveBufferSnapshot.idle(),
  );

  final List<_LiveSegment> _segments = [];
  final Completer<void> _initialBufferReady = Completer<void>();
  final Completer<void> _stopSignal = Completer<void>();
  late final String _accessKey = _randomAccessKey();
  HttpClient? _httpClient;
  StreamIterator<List<int>>? _upstreamIterator;
  HttpServer? _server;
  RandomAccessFile? _writer;
  Future<void>? _recordingTask;
  Completer<void> _dataAvailable = Completer<void>();
  double _liveEdgeMicros = 0;
  int _nextSegmentSequence = 0;
  bool _stopping = false;
  DateTime _lastStatePublish = DateTime.fromMillisecondsSinceEpoch(0);

  Duration get bufferStart => state.value.bufferStart;

  Duration get liveEdge => state.value.liveEdge;

  bool get isStopped => _stopping;

  String get mimeType =>
      format == LiveAudioFormat.mp3 ? 'audio/mpeg' : 'audio/aac';

  String get fileExtension => format == LiveAudioFormat.mp3 ? 'mp3' : 'aac';

  Future<void> start() async {
    await directory.create(recursive: true);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(
      _handleLocalRequest,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Live relay server error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    _recordingTask = _recordLoop();

    try {
      await _initialBufferReady.future.timeout(startupTimeout);
    } on TimeoutException {
      await stop();
      throw TimeoutException(
        'The live stream did not provide audio in time.',
        startupTimeout,
      );
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  LivePlaybackEndpoint endpointAt(
    Duration requested, {
    bool nearLiveEdge = false,
  }) {
    if (_segments.isEmpty) {
      throw StateError('The live buffer has no playable audio yet.');
    }

    var target = requested;
    if (nearLiveEdge || target >= liveEdge) {
      target = liveEdge - initialBuffer;
    }
    target = _clampDuration(target, bufferStart, liveEdge);
    final location = _locateFrame(target);
    final server = _server;
    if (location == null || server == null) {
      throw StateError('The requested live position is no longer available.');
    }

    return LivePlaybackEndpoint(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/live.$fileExtension',
        queryParameters: {
          'key': _accessKey,
          'segment': '${location.segment.sequence}',
          'offset': '${location.byteOffset}',
        },
      ),
      position: Duration(microseconds: location.positionMicros),
    );
  }

  Future<void> stop() async {
    if (_stopping) {
      return;
    }
    _stopping = true;
    if (!_stopSignal.isCompleted) {
      _stopSignal.complete();
    }
    _signalDataAvailable();
    final upstreamIterator = _upstreamIterator;
    _upstreamIterator = null;
    await upstreamIterator?.cancel();
    _httpClient?.close(force: true);
    await _server?.close(force: true);

    final recordingTask = _recordingTask;
    if (recordingTask != null) {
      try {
        await recordingTask;
      } catch (_) {
        // Recording failures are already reflected in the session state.
      }
    }
    await _closeWriter();
    state.value = const LiveBufferSnapshot.idle();
    await _deleteDirectoryWithRetry();
    state.dispose();
  }

  Future<void> _recordLoop() async {
    var reconnectAttempt = 0;
    while (!_stopping) {
      _publishState(
        phase: _segments.isEmpty
            ? LiveTimeshiftPhase.connecting
            : LiveTimeshiftPhase.reconnecting,
        force: true,
      );

      final parser = LiveAudioFrameParser(format);
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        _httpClient = client;
        final request = await client.getUrl(sourceUri);
        request.followRedirects = true;
        request.maxRedirects = 5;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'talkSPORT Companion/1.0',
        );
        request.headers.set('Icy-MetaData', '0');
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException(
            'Live stream returned HTTP ${response.statusCode}.',
            uri: sourceUri,
          );
        }

        reconnectAttempt = 0;
        var receivedAudio = false;
        final iterator = StreamIterator<List<int>>(response);
        _upstreamIterator = iterator;
        while (!_stopping &&
            await iterator.moveNext().timeout(_upstreamSilenceTimeout)) {
          final chunk = iterator.current;
          final frames = parser.add(chunk);
          if (frames.isEmpty) {
            continue;
          }
          await _appendFrames(frames);
          _signalDataAvailable();
          _publishState(
            phase: LiveTimeshiftPhase.ready,
            clearError: !receivedAudio,
            force: !receivedAudio,
          );
          receivedAudio = true;
        }
        await iterator.cancel();
        if (identical(_upstreamIterator, iterator)) {
          _upstreamIterator = null;
        }
        if (!_stopping) {
          throw const HttpException('The live stream connection closed.');
        }
      } catch (error, stackTrace) {
        if (_stopping) {
          break;
        }
        reconnectAttempt += 1;
        debugPrint('Live stream reconnect $reconnectAttempt after: $error');
        debugPrintStack(stackTrace: stackTrace);
        _publishState(
          phase: _segments.isEmpty
              ? LiveTimeshiftPhase.connecting
              : LiveTimeshiftPhase.reconnecting,
          errorMessage: error.toString(),
          force: true,
        );
        final delaySeconds = min(30, 1 << min(reconnectAttempt - 1, 5));
        await Future.any<void>([
          Future<void>.delayed(Duration(seconds: delaySeconds)),
          _stopSignal.future,
        ]);
      } finally {
        final iterator = _upstreamIterator;
        _upstreamIterator = null;
        await iterator?.cancel();
        _httpClient?.close(force: true);
        _httpClient = null;
      }
    }
  }

  Future<void> _appendFrames(List<LiveAudioFrame> frames) async {
    for (final frame in frames) {
      var segment = _segments.lastOrNull;
      if (segment == null ||
          segment.duration >= segmentDuration.inMicroseconds) {
        if (segment != null) {
          await _finalizeSegment(segment);
        }
        segment = await _createSegment();
      }

      final writer = _writer;
      if (writer == null) {
        throw StateError('The live buffer writer is unavailable.');
      }
      final frameStartMicros = _liveEdgeMicros.round();
      segment.framePositionsMicros.add(frameStartMicros);
      segment.frameOffsets.add(segment.byteLength);
      await writer.writeFrom(frame.bytes);
      segment.byteLength += frame.bytes.length;
      _liveEdgeMicros +=
          frame.sampleCount * Duration.microsecondsPerSecond / frame.sampleRate;
      segment.endMicros = _liveEdgeMicros.round();
    }

    if (!_initialBufferReady.isCompleted &&
        _liveEdgeMicros >= initialBuffer.inMicroseconds) {
      _initialBufferReady.complete();
    }
    await _pruneExpiredSegments();
  }

  Future<_LiveSegment> _createSegment() async {
    final sequence = _nextSegmentSequence++;
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'segment-${sequence.toString().padLeft(6, '0')}.$fileExtension',
    );
    final segment = _LiveSegment(
      sequence: sequence,
      file: file,
      startMicros: _liveEdgeMicros.round(),
    );
    _segments.add(segment);
    _writer = await file.open(mode: FileMode.writeOnly);
    return segment;
  }

  Future<void> _finalizeSegment(_LiveSegment segment) async {
    segment.finalized = true;
    await _closeWriter();
    _signalDataAvailable();
  }

  Future<void> _closeWriter() async {
    final writer = _writer;
    _writer = null;
    if (writer == null) {
      return;
    }
    try {
      await writer.flush();
      await writer.close();
    } catch (error) {
      debugPrint('Could not close live buffer writer: $error');
    }
  }

  Future<void> _pruneExpiredSegments() async {
    final cutoffMicros = _liveEdgeMicros.round() - maximumBuffer.inMicroseconds;
    var changed = false;
    while (_segments.length > 1 && _segments.first.endMicros <= cutoffMicros) {
      final expired = _segments.removeAt(0)..pendingDelete = true;
      changed = true;
      await _deleteSegmentIfUnused(expired);
    }
    if (changed) {
      _publishState(phase: state.value.phase, force: true);
      _signalDataAvailable();
    }
  }

  _FrameLocation? _locateFrame(Duration requested) {
    final targetMicros = requested.inMicroseconds;
    _LiveSegment? segment;
    for (final candidate in _segments) {
      if (targetMicros < candidate.endMicros ||
          identical(candidate, _segments.last)) {
        segment = candidate;
        break;
      }
    }
    segment ??= _segments.lastOrNull;
    if (segment == null || segment.framePositionsMicros.isEmpty) {
      return null;
    }

    var low = 0;
    var high = segment.framePositionsMicros.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (segment.framePositionsMicros[middle] <= targetMicros) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return _FrameLocation(
      segment: segment,
      byteOffset: segment.frameOffsets[low],
      positionMicros: segment.framePositionsMicros[low],
    );
  }

  Future<void> _handleLocalRequest(HttpRequest request) async {
    final key = request.uri.queryParameters['key'];
    final sequence = int.tryParse(request.uri.queryParameters['segment'] ?? '');
    final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
    if (request.uri.path != '/live.$fileExtension' ||
        key != _accessKey ||
        sequence == null ||
        offset == null ||
        offset < 0) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final firstSegment = _segmentForSequence(sequence);
    if (firstSegment == null || offset > firstSegment.byteLength) {
      request.response.statusCode = HttpStatus.gone;
      await request.response.close();
      return;
    }

    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.parse(mimeType);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.bufferOutput = false;

    var segment = firstSegment;
    var readOffset = offset;
    try {
      while (!_stopping) {
        await _streamSegment(segment, readOffset, response);
        if (_stopping || segment.pendingDelete) {
          break;
        }
        final nextSequence = segment.sequence + 1;
        var next = _segmentForSequence(nextSequence);
        // Finalizing one segment and creating the next are separate async file
        // operations. Keep the relay open across that brief hand-off instead of
        // exposing an artificial end-of-stream to the audio player.
        while (next == null && !segment.pendingDelete && !_stopping) {
          await _waitForData();
          next = _segmentForSequence(nextSequence);
        }
        if (next == null) {
          break;
        }
        segment = next;
        readOffset = 0;
      }
    } catch (_) {
      // The player routinely closes relay requests when seeking or stopping.
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The client has already disconnected.
      }
    }
  }

  Future<void> _streamSegment(
    _LiveSegment segment,
    int startOffset,
    HttpResponse response,
  ) async {
    segment.readers += 1;
    RandomAccessFile? reader;
    try {
      reader = await segment.file.open(mode: FileMode.read);
      await reader.setPosition(startOffset);
      var readOffset = startOffset;
      while (!_stopping) {
        final availableLength = await segment.file.length();
        if (readOffset < availableLength) {
          final readLength = min(16 * 1024, availableLength - readOffset);
          final bytes = await reader.read(readLength);
          if (bytes.isEmpty) {
            await _waitForData();
            continue;
          }
          readOffset += bytes.length;
          response.add(bytes);
          await response.flush();
          continue;
        }
        if (segment.finalized || segment.pendingDelete) {
          break;
        }
        await _waitForData();
      }
    } finally {
      await reader?.close();
      segment.readers -= 1;
      await _deleteSegmentIfUnused(segment);
    }
  }

  _LiveSegment? _segmentForSequence(int sequence) {
    for (final segment in _segments) {
      if (segment.sequence == sequence) {
        return segment;
      }
    }
    return null;
  }

  Future<void> _deleteSegmentIfUnused(_LiveSegment segment) async {
    if (!segment.pendingDelete || segment.readers > 0) {
      return;
    }
    try {
      if (await segment.file.exists()) {
        await segment.file.delete();
      }
    } catch (error) {
      debugPrint('Could not prune live buffer segment: $error');
    }
  }

  Future<void> _waitForData() async {
    final signal = _dataAvailable.future;
    await Future.any<void>([
      signal,
      Future<void>.delayed(const Duration(milliseconds: 500)),
      _stopSignal.future,
    ]);
  }

  void _signalDataAvailable() {
    final previous = _dataAvailable;
    _dataAvailable = Completer<void>();
    if (!previous.isCompleted) {
      previous.complete();
    }
  }

  void _publishState({
    required LiveTimeshiftPhase phase,
    String? errorMessage,
    bool clearError = false,
    bool force = false,
  }) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastStatePublish) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastStatePublish = now;
    final first = _segments.firstOrNull;
    final current = state.value;
    state.value = LiveBufferSnapshot(
      phase: phase,
      bufferStart: Duration(microseconds: first?.startMicros ?? 0),
      liveEdge: Duration(microseconds: _liveEdgeMicros.round()),
      observedAt: now,
      errorMessage: clearError ? null : errorMessage ?? current.errorMessage,
    );
  }

  Future<void> _deleteDirectoryWithRetry() async {
    for (var attempt = 0; attempt < 4; attempt += 1) {
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        return;
      } catch (error) {
        if (attempt == 3) {
          debugPrint('Could not remove live buffer ${directory.path}: $error');
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
  }

  static Duration _clampDuration(
    Duration value,
    Duration minimum,
    Duration maximum,
  ) {
    if (value < minimum) {
      return minimum;
    }
    if (value > maximum) {
      return maximum;
    }
    return value;
  }

  static String _randomAccessKey() {
    final random = Random.secure();
    return List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16),
    ).join();
  }

  static const _upstreamSilenceTimeout = Duration(seconds: 8);
}

class _LiveSegment {
  _LiveSegment({
    required this.sequence,
    required this.file,
    required this.startMicros,
  }) : endMicros = startMicros;

  final int sequence;
  final File file;
  final int startMicros;
  final List<int> framePositionsMicros = [];
  final List<int> frameOffsets = [];
  int endMicros;
  int byteLength = 0;
  int readers = 0;
  bool finalized = false;
  bool pendingDelete = false;

  int get duration => endMicros - startMicros;
}

class _FrameLocation {
  const _FrameLocation({
    required this.segment,
    required this.byteOffset,
    required this.positionMicros,
  });

  final _LiveSegment segment;
  final int byteOffset;
  final int positionMicros;
}
