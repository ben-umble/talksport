// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Recording _$RecordingFromJson(Map<String, dynamic> json) => Recording(
  url: json['url'] as String,
  duration: (json['duration'] as num).toInt(),
);

Map<String, dynamic> _$RecordingToJson(Recording instance) => <String, dynamic>{
  'url': instance.url,
  'duration': instance.duration,
};
