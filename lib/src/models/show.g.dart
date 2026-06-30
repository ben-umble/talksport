// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'show.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Show _$ShowFromJson(Map<String, dynamic> json) => Show(
  id: json['id'] as String? ?? '',
  title: json['title'] as String? ?? '',
  programmeTitle: json['programmeTitle'] as String? ?? '',
  startTime: dateTimeFromJson(json['startTime'] as String),
  endTime: dateTimeFromJson(json['endTime'] as String),
  description: json['description'] as String? ?? '',
  images: stringMapFromJson(json['images']),
  recording: json['recording'] == null
      ? null
      : Recording.fromJson(json['recording'] as Map<String, dynamic>),
  liveVideo: stringMapFromJson(json['liveVideo']),
  stationId: json['station_id'] as String? ?? '',
  stationSlug: json['stationSlug'] as String? ?? '',
);

Map<String, dynamic> _$ShowToJson(Show instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'programmeTitle': instance.programmeTitle,
  'startTime': dateTimeToJson(instance.startTime),
  'endTime': dateTimeToJson(instance.endTime),
  'description': instance.description,
  'images': instance.images,
  'recording': instance.recording?.toJson(),
  'liveVideo': instance.liveVideo,
  'station_id': instance.stationId,
  'stationSlug': instance.stationSlug,
};
