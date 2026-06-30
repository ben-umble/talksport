import 'package:json_annotation/json_annotation.dart';

import 'show.dart';

part 'schedule_day.g.dart';

@JsonSerializable(explicitToJson: true)
class ScheduleDay {
  const ScheduleDay({
    required this.date,
    required this.shows,
    required this.itemId,
    required this.dayNumber,
  });

  factory ScheduleDay.fromJson(Map<String, dynamic> json) =>
      _$ScheduleDayFromJson(json);

  @JsonKey(defaultValue: '')
  final String date;

  @JsonKey(defaultValue: <Show>[])
  final List<Show> shows;

  @JsonKey(defaultValue: '')
  final String itemId;

  @JsonKey(defaultValue: 0)
  final int dayNumber;

  bool get isPastOrToday => dayNumber <= 0;

  Map<String, dynamic> toJson() => _$ScheduleDayToJson(this);
}
