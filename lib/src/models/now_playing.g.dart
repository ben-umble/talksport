// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'now_playing.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NowPlaying _$NowPlayingFromJson(Map<String, dynamic> json) => NowPlaying(
  title: json['title'] as String? ?? '',
  id: json['id'] as String? ?? '',
  description: json['description'] as String? ?? '',
  programmeTitle: json['programmeTitle'] as String? ?? '',
  images: stringMapFromJson(json['images']),
  startTime: dateTimeFromJson(json['startTime'] as String),
  endTime: dateTimeFromJson(json['endTime'] as String),
  liveVideo: stringMapFromJson(json['liveVideo']),
  hasLiveStream: json['hasLiveStream'] as bool? ?? false,
  nextShow: json['nextShow'] == null
      ? null
      : Show.fromJson(json['nextShow'] as Map<String, dynamic>),
  stationSlug: json['stationSlug'] as String? ?? '',
  stationId: json['station_id'] as String? ?? '',
  type: json['type'] as String? ?? 'live',
);

Map<String, dynamic> _$NowPlayingToJson(NowPlaying instance) =>
    <String, dynamic>{
      'title': instance.title,
      'id': instance.id,
      'description': instance.description,
      'programmeTitle': instance.programmeTitle,
      'images': instance.images,
      'startTime': dateTimeToJson(instance.startTime),
      'endTime': dateTimeToJson(instance.endTime),
      'liveVideo': instance.liveVideo,
      'hasLiveStream': instance.hasLiveStream,
      'nextShow': instance.nextShow?.toJson(),
      'stationSlug': instance.stationSlug,
      'station_id': instance.stationId,
      'type': instance.type,
    };
