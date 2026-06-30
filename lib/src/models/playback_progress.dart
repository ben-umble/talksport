import 'package:json_annotation/json_annotation.dart';

part 'playback_progress.g.dart';

@JsonSerializable()
class PlaybackProgress {
  const PlaybackProgress({
    required this.playbackId,
    required this.stationSlug,
    required this.positionMs,
    required this.updatedAtMs,
  });

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) =>
      _$PlaybackProgressFromJson(json);

  final String playbackId;
  final String stationSlug;
  final int positionMs;
  final int updatedAtMs;

  Duration get position => Duration(milliseconds: positionMs);

  Map<String, dynamic> toJson() => _$PlaybackProgressToJson(this);
}
