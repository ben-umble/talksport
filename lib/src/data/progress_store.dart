import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playback_item.dart';
import '../models/playback_progress.dart';

class ProgressStore {
  ProgressStore._({this.preferences, this.memory});

  static Future<ProgressStore> create() async {
    return ProgressStore._(preferences: await SharedPreferences.getInstance());
  }

  factory ProgressStore.memory() => ProgressStore._(memory: <String, String>{});

  static const _progressPrefix = 'progress.';
  static const _lastItemKey = 'lastPlaybackItem';

  final SharedPreferences? preferences;
  final Map<String, String>? memory;

  Future<void> saveProgress(PlaybackItem item, Duration position) async {
    if (!item.isCatchUp) {
      return;
    }
    final progress = PlaybackProgress(
      playbackId: item.id,
      stationSlug: item.stationSlug,
      positionMs: position.inMilliseconds,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _setString('$_progressPrefix${item.id}', jsonEncode(progress));
    await saveLastItem(item);
  }

  PlaybackProgress? progressFor(String playbackId) {
    final raw = _getString('$_progressPrefix$playbackId');
    if (raw == null) {
      return null;
    }
    try {
      return PlaybackProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastItem(PlaybackItem item) async {
    await _setString(_lastItemKey, jsonEncode(item.toJson()));
  }

  PlaybackItem? lastItem() {
    final raw = _getString(_lastItemKey);
    if (raw == null) {
      return null;
    }
    try {
      return PlaybackItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String? _getString(String key) {
    final memory = this.memory;
    if (memory != null) {
      return memory[key];
    }
    return preferences?.getString(key);
  }

  Future<void> _setString(String key, String value) async {
    final memory = this.memory;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    await preferences?.setString(key, value);
  }
}
