import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../models/now_playing.dart';
import '../models/schedule_day.dart';

abstract class TalkSportPageScraper {
  Future<TalkSportPagePayload> fetch(String stationSlug);

  static TalkSportPageScraper? maybeCreate() {
    if (Platform.isWindows) {
      return WindowsTalkSportPageScraper();
    }
    return null;
  }
}

class TalkSportPagePayload {
  const TalkSportPagePayload({
    required this.nowPlaying,
    required this.schedule,
  });

  final NowPlaying nowPlaying;
  final List<ScheduleDay> schedule;
}

class WindowsTalkSportPageScraper implements TalkSportPageScraper {
  WindowsTalkSportPageScraper();

  final Map<String, _PageCacheEntry> _cache = {};
  final Map<String, Future<TalkSportPagePayload>> _inFlight = {};
  WebviewController? _controller;
  Future<void>? _initializing;
  static Future<void>? _environmentInitialization;

  @override
  Future<TalkSportPagePayload> fetch(String stationSlug) {
    final cached = _cache[stationSlug];
    if (cached != null && cached.isFresh) {
      return Future.value(cached.payload);
    }

    final existing = _inFlight[stationSlug];
    if (existing != null) {
      return existing;
    }

    final request = _load(stationSlug).whenComplete(
      () => _inFlight.remove(stationSlug),
    );
    _inFlight[stationSlug] = request;
    return request;
  }

  Future<void> _ensureInitialized() {
    final initializing = _initializing;
    if (initializing != null) {
      return initializing;
    }

    return _initializing = () async {
      final version = await WebviewController.getWebViewVersion();
      if (version == null) {
        throw const TalkSportPageScraperException(
          'Microsoft Edge WebView2 Runtime is not installed.',
        );
      }

      await _ensurePersistentEnvironment();
      final controller = WebviewController();
      _controller = controller;
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
      );
    }();
  }

  Future<TalkSportPagePayload> _load(String stationSlug) async {
    await _ensureInitialized();
    final controller = _controller;
    if (controller == null) {
      throw const TalkSportPageScraperException('WebView is not initialized.');
    }
    await controller.loadUrl('https://talksport.com/play/$stationSlug');

    final deadline = DateTime.now().add(const Duration(seconds: 35));
    Object? lastResult;
    Object? lastError;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      try {
        lastResult = await controller.executeScript(_extractorScript);
        final payload = _payloadFromScriptResult(lastResult);
        if (payload != null) {
          _cache[stationSlug] = _PageCacheEntry(payload, DateTime.now());
          return payload;
        }
      } catch (error) {
        lastError = error;
      }
    }

    throw TalkSportPageScraperException(
      'Timed out while reading talkSPORT page metadata. '
      'Last result: $lastResult. Last error: $lastError',
    );
  }

  TalkSportPagePayload? _payloadFromScriptResult(Object? result) {
    if (result == null) {
      return null;
    }

    final text = result is String ? result : jsonEncode(result);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    if (decoded['error'] != null) {
      return null;
    }

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

    return TalkSportPagePayload(
      nowPlaying: NowPlaying.fromJson(onAirNow),
      schedule: days,
    );
  }

  static Future<void> _ensurePersistentEnvironment() {
    final initialization = _environmentInitialization;
    if (initialization != null) {
      return initialization;
    }

    return _environmentInitialization = () async {
      final directory = Directory(_webViewUserDataPath());
      await directory.create(recursive: true);
      try {
        await WebviewController.initializeEnvironment(
          userDataPath: directory.path,
        );
      } on PlatformException catch (error) {
        if (!error.message.toString().contains('initialized')) {
          rethrow;
        }
      }
    }();
  }

  static String _webViewUserDataPath() {
    final root = Platform.environment['LOCALAPPDATA'];
    final base = root == null || root.isEmpty ? Directory.systemTemp.path : root;
    return [
      base,
      'talkSPORT Companion',
      'WebView2',
    ].join(Platform.pathSeparator);
  }
}

class TalkSportPageScraperException implements Exception {
  const TalkSportPageScraperException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PageCacheEntry {
  const _PageCacheEntry(this.payload, this.createdAt);

  final TalkSportPagePayload payload;
  final DateTime createdAt;

  bool get isFresh => DateTime.now().difference(createdAt).inMinutes < 5;
}

const _extractorScript = r'''
(() => {
  function decodeScriptChunks() {
    const chunks = [];
    const scripts = Array.from(document.scripts || []);
    for (const script of scripts) {
      const text = script.textContent || '';
      if (!text.includes('__next_f.push')) continue;
      const re = /self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)/g;
      let match;
      while ((match = re.exec(text)) !== null) {
        try {
          chunks.push(JSON.parse('"' + match[1] + '"'));
        } catch (_) {
          chunks.push(match[1]);
        }
      }
    }
    return chunks.join('\n');
  }

  function extractPayload() {
    const joined = decodeScriptChunks();
    const marker = '"onAirNow":';
    const markerIndex = joined.indexOf(marker);
    if (markerIndex < 0) {
      return { error: 'onAirNow marker missing', length: joined.length };
    }

    const objectStart = joined.lastIndexOf('{', markerIndex);
    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let i = objectStart; i < joined.length; i++) {
      const ch = joined[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if (ch === '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch === '{') depth++;
      if (ch === '}') {
        depth--;
        if (depth === 0) {
          const candidate = joined.slice(objectStart, i + 1);
          try {
            const obj = JSON.parse(candidate);
            return {
              onAirNow: obj.onAirNow,
              schedule: obj.schedule,
              stationSlug: obj.stationSlug || (obj.onAirNow && obj.onAirNow.stationSlug),
            };
          } catch (error) {
            return { error: String(error) };
          }
        }
      }
    }

    return { error: 'payload end missing', length: joined.length };
  }

  return JSON.stringify(extractPayload());
})()
''';
