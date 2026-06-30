// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_day.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScheduleDay _$ScheduleDayFromJson(Map<String, dynamic> json) => ScheduleDay(
  date: json['date'] as String? ?? '',
  shows:
      (json['shows'] as List<dynamic>?)
          ?.map((e) => Show.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  itemId: json['itemId'] as String? ?? '',
  dayNumber: (json['dayNumber'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$ScheduleDayToJson(ScheduleDay instance) =>
    <String, dynamic>{
      'date': instance.date,
      'shows': instance.shows.map((e) => e.toJson()).toList(),
      'itemId': instance.itemId,
      'dayNumber': instance.dayNumber,
    };
