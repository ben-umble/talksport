import 'package:json_annotation/json_annotation.dart';

import 'json_helpers.dart';
import 'recording.dart';

part 'show.g.dart';

@JsonSerializable(explicitToJson: true)
class Show {
  const Show({
    required this.id,
    required this.title,
    required this.programmeTitle,
    required this.startTime,
    required this.endTime,
    required this.description,
    required this.images,
    required this.recording,
    required this.liveVideo,
    required this.stationId,
    required this.stationSlug,
  });

  factory Show.fromJson(Map<String, dynamic> json) => _$ShowFromJson(json);

  @JsonKey(defaultValue: '')
  final String id;

  @JsonKey(defaultValue: '')
  final String title;

  @JsonKey(defaultValue: '')
  final String programmeTitle;

  @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
  final DateTime startTime;

  @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
  final DateTime endTime;

  @JsonKey(defaultValue: '')
  final String description;

  @JsonKey(fromJson: stringMapFromJson)
  final Map<String, String> images;

  final Recording? recording;

  @JsonKey(fromJson: stringMapFromJson)
  final Map<String, String> liveVideo;

  @JsonKey(name: 'station_id', defaultValue: '')
  final String stationId;

  @JsonKey(defaultValue: '')
  final String stationSlug;

  bool get hasRecording => recording?.url.isNotEmpty ?? false;

  String? get thumbnailUrl {
    final thumbnail = images['thumbnail'];
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return thumbnail;
    }
    final presenter = images['presenter'];
    return presenter != null && presenter.isNotEmpty ? presenter : null;
  }

  Duration get scheduledDuration => endTime.difference(startTime);

  Map<String, dynamic> toJson() => _$ShowToJson(this);
}
