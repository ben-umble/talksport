import 'package:json_annotation/json_annotation.dart';

part 'recording.g.dart';

@JsonSerializable()
class Recording {
  const Recording({
    required this.url,
    required this.duration,
  });

  factory Recording.fromJson(Map<String, dynamic> json) =>
      _$RecordingFromJson(json);

  final String url;

  /// The talkSPORT API returns recording durations in milliseconds.
  final int duration;

  Duration get durationValue => Duration(milliseconds: duration);

  Map<String, dynamic> toJson() => _$RecordingToJson(this);
}
