import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/playback_item.dart';

class CatchUpDownloadCache {
  CatchUpDownloadCache({
    http.Client? client,
    this.rootDirectory,
    this.retention = defaultRetention,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const defaultRetention = Duration(days: 7);
  static const _orphanGracePeriod = Duration(hours: 1);

  final http.Client _client;
  final bool _ownsClient;
  final Duration retention;
  Directory? rootDirectory;
  final Map<String, Future<File?>> _downloads = {};

  static Future<Directory> defaultRootDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(_joinPath(supportDirectory.path, 'catch_up_audio'));
  }

  Future<File?> cachedFileFor(PlaybackItem item) async {
    if (!_canCache(item)) {
      return null;
    }

    final file = await fileFor(item);
    final marker = _completeMarkerFor(file);
    if (!await file.exists() || !await marker.exists()) {
      return null;
    }

    if (await _isExpired(marker, DateTime.now().toUtc())) {
      await _deleteCachePair(file, marker);
      return null;
    }

    final length = await file.length();
    return length > 0 ? file : null;
  }

  Future<File> fileFor(PlaybackItem item) async {
    final root = await _resolveRootDirectory();
    return File(_joinPath(root.path, _fileNameFor(item)));
  }

  Future<File?> download(PlaybackItem item) {
    if (!_canCache(item)) {
      return Future.value(null);
    }

    final key = _cacheKey(item);
    final existing = _downloads[key];
    if (existing != null) {
      return existing;
    }

    late final Future<File?> download;
    download = _download(item).whenComplete(() {
      _downloads.remove(key);
    });
    _downloads[key] = download;
    return download;
  }

  void ensureDownloadStarted(
    PlaybackItem item, {
    void Function(File file)? onComplete,
  }) {
    if (!_canCache(item)) {
      return;
    }

    unawaited(
      download(item)
          .then((file) {
            if (file != null) {
              onComplete?.call(file);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('Could not cache catch-up audio: $error');
            debugPrintStack(stackTrace: stackTrace);
          }),
    );
  }

  Future<int> cleanExpired({DateTime? now}) async {
    final root = await _resolveRootDirectory();
    if (!await root.exists()) {
      return 0;
    }

    final currentTime = (now ?? DateTime.now()).toUtc();
    var deleted = 0;
    final entries = await root.list(followLinks: false).toList();

    for (final entry in entries.whereType<File>()) {
      final path = entry.path;
      if (path.endsWith('.complete')) {
        final audio = File(path.substring(0, path.length - '.complete'.length));
        if (!await audio.exists()) {
          deleted += await _deleteFile(entry);
          continue;
        }
        if (await _isExpired(entry, currentTime)) {
          deleted += await _deleteCachePair(audio, entry);
        }
        continue;
      }

      if (path.endsWith('.part')) {
        if (await _isOlderThan(entry, _orphanGracePeriod, currentTime)) {
          deleted += await _deleteFile(entry);
        }
        continue;
      }

      if (path.endsWith('.mp3')) {
        final marker = _completeMarkerFor(entry);
        if (!await marker.exists() &&
            await _isOlderThan(entry, _orphanGracePeriod, currentTime)) {
          deleted += await _deleteFile(entry);
        }
      }
    }

    return deleted;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<File?> _download(PlaybackItem item) async {
    final cached = await cachedFileFor(item);
    if (cached != null) {
      return cached;
    }

    final target = await fileFor(item);
    final marker = _completeMarkerFor(target);
    await target.parent.create(recursive: true);
    if (await marker.exists()) {
      await marker.delete();
    }
    if (await target.exists()) {
      await target.delete();
    }

    try {
      final request = http.Request('GET', Uri.parse(item.audioUrl))
        ..headers.addAll({
          'Accept': 'audio/mpeg,audio/*;q=0.9,*/*;q=0.8',
          'User-Agent': 'talkSPORT Companion/1.0',
        });
      final response = await _client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Audio download failed with HTTP ${response.statusCode}',
          uri: request.url,
        );
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/html')) {
        throw HttpException(
          'Audio download returned HTML instead of an audio file',
          uri: request.url,
        );
      }

      final sink = target.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        rethrow;
      }

      if (await target.length() == 0) {
        throw StateError('Audio download completed with an empty file.');
      }

      await marker.writeAsString(DateTime.now().toUtc().toIso8601String());
      return target;
    } catch (_) {
      if (await marker.exists()) {
        await marker.delete();
      }
      if (await target.exists()) {
        await target.delete();
      }
      rethrow;
    }
  }

  Future<Directory> _resolveRootDirectory() async {
    final existing = rootDirectory;
    if (existing != null) {
      await existing.create(recursive: true);
      return existing;
    }

    final directory = await defaultRootDirectory();
    await directory.create(recursive: true);
    rootDirectory = directory;
    return directory;
  }

  bool _canCache(PlaybackItem item) =>
      item.isCatchUp && item.audioUrl.isNotEmpty;

  String _cacheKey(PlaybackItem item) => '${item.stationSlug}:${item.id}';

  String _fileNameFor(PlaybackItem item) {
    final station = _sanitizeFilePart(item.stationSlug);
    final id = _sanitizeFilePart(item.id);
    return '${station}_$id.mp3';
  }

  File _completeMarkerFor(File file) => File('${file.path}.complete');

  Future<bool> _isExpired(File marker, DateTime now) async {
    final completedAt = await _completionTime(marker);
    return completedAt.add(retention).isBefore(now);
  }

  Future<bool> _isOlderThan(File file, Duration age, DateTime now) async {
    final modifiedAt = (await file.lastModified()).toUtc();
    return modifiedAt.add(age).isBefore(now);
  }

  Future<DateTime> _completionTime(File marker) async {
    try {
      final raw = await marker.readAsString();
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) {
        return parsed.toUtc();
      }
    } catch (_) {
      // Fall back to filesystem metadata if the marker contents are unreadable.
    }

    return (await marker.lastModified()).toUtc();
  }

  Future<int> _deleteCachePair(File audio, File marker) async {
    var deleted = 0;
    deleted += await _deleteFile(audio);
    deleted += await _deleteFile(marker);
    return deleted;
  }

  Future<int> _deleteFile(File file) async {
    try {
      if (!await file.exists()) {
        return 0;
      }
      await file.delete();
      return 1;
    } catch (error, stackTrace) {
      debugPrint('Could not delete cached audio file ${file.path}: $error');
      debugPrintStack(stackTrace: stackTrace);
      return 0;
    }
  }

  String _sanitizeFilePart(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'audio' : cleaned;
  }

  static String _joinPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }
}
