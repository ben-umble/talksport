// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlaybackProgress _$PlaybackProgressFromJson(Map<String, dynamic> json) =>
    PlaybackProgress(
      playbackId: json['playbackId'] as String,
      stationSlug: json['stationSlug'] as String,
      positionMs: (json['positionMs'] as num).toInt(),
      updatedAtMs: (json['updatedAtMs'] as num).toInt(),
    );

Map<String, dynamic> _$PlaybackProgressToJson(PlaybackProgress instance) =>
    <String, dynamic>{
      'playbackId': instance.playbackId,
      'stationSlug': instance.stationSlug,
      'positionMs': instance.positionMs,
      'updatedAtMs': instance.updatedAtMs,
    };
