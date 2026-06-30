import 'package:audio_service/audio_service.dart';

import 'now_playing.dart';
import 'show.dart';
import 'station.dart';

enum PlaybackKind { live, catchUp }

class PlaybackItem {
  const PlaybackItem({
    required this.id,
    required this.kind,
    required this.stationSlug,
    required this.stationName,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.audioUrl,
    required this.imageUrl,
    required this.duration,
  });

  factory PlaybackItem.live(Station station, NowPlaying nowPlaying) {
    return PlaybackItem(
      id: 'live:${station.slug}',
      kind: PlaybackKind.live,
      stationSlug: station.slug,
      stationName: station.name,
      title: nowPlaying.title.isEmpty ? station.name : nowPlaying.title,
      subtitle: 'Live on ${station.name}',
      description: nowPlaying.description,
      audioUrl: station.liveStreamUrl,
      imageUrl: nowPlaying.thumbnailUrl,
      duration: null,
    );
  }

  factory PlaybackItem.catchUp(Station station, Show show) {
    final recording = show.recording;
    return PlaybackItem(
      id: show.id,
      kind: PlaybackKind.catchUp,
      stationSlug: station.slug,
      stationName: station.name,
      title: show.title,
      subtitle: station.name,
      description: show.description,
      audioUrl: recording?.url ?? '',
      imageUrl: show.thumbnailUrl,
      duration: recording?.durationValue,
    );
  }

  factory PlaybackItem.fromJson(Map<String, dynamic> json) {
    final durationMs = json['durationMs'] as int?;
    return PlaybackItem(
      id: json['id'] as String,
      kind: PlaybackKind.values.byName(json['kind'] as String),
      stationSlug: json['stationSlug'] as String,
      stationName: json['stationName'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      description: json['description'] as String? ?? '',
      audioUrl: json['audioUrl'] as String,
      imageUrl: json['imageUrl'] as String?,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
  }

  final String id;
  final PlaybackKind kind;
  final String stationSlug;
  final String stationName;
  final String title;
  final String subtitle;
  final String description;
  final String audioUrl;
  final String? imageUrl;
  final Duration? duration;

  bool get isLive => kind == PlaybackKind.live;
  bool get isCatchUp => kind == PlaybackKind.catchUp;

  MediaItem toMediaItem() {
    final art = imageUrl;
    return MediaItem(
      id: audioUrl,
      title: title,
      artist: subtitle,
      album: stationName,
      duration: duration,
      artUri: art == null || art.isEmpty ? null : Uri.tryParse(art),
      extras: {
        'playbackId': id,
        'kind': kind.name,
        'stationSlug': stationSlug,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'stationSlug': stationSlug,
      'stationName': stationName,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'audioUrl': audioUrl,
      'imageUrl': imageUrl,
      'durationMs': duration?.inMilliseconds,
    };
  }
}
