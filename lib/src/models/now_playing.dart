import 'package:json_annotation/json_annotation.dart';

import 'json_helpers.dart';
import 'show.dart';

part 'now_playing.g.dart';

@JsonSerializable(explicitToJson: true)
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.id,
    required this.description,
    required this.programmeTitle,
    required this.images,
    required this.startTime,
    required this.endTime,
    required this.liveVideo,
    required this.hasLiveStream,
    required this.nextShow,
    required this.stationSlug,
    required this.stationId,
    required this.type,
  });

  factory NowPlaying.fromJson(Map<String, dynamic> json) =>
      _$NowPlayingFromJson(json);

  @JsonKey(defaultValue: '')
  final String title;

  @JsonKey(defaultValue: '')
  final String id;

  @JsonKey(defaultValue: '')
  final String description;

  @JsonKey(defaultValue: '')
  final String programmeTitle;

  @JsonKey(fromJson: stringMapFromJson)
  final Map<String, String> images;

  @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
  final DateTime startTime;

  @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
  final DateTime endTime;

  @JsonKey(fromJson: stringMapFromJson)
  final Map<String, String> liveVideo;

  @JsonKey(defaultValue: false)
  final bool hasLiveStream;

  final Show? nextShow;

  @JsonKey(defaultValue: '')
  final String stationSlug;

  @JsonKey(name: 'station_id', defaultValue: '')
  final String stationId;

  @JsonKey(defaultValue: 'live')
  final String type;

  String? get thumbnailUrl {
    final thumbnail = images['thumbnail'];
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return thumbnail;
    }
    final presenter = images['presenter'];
    return presenter != null && presenter.isNotEmpty ? presenter : null;
  }

  Map<String, dynamic> toJson() => _$NowPlayingToJson(this);
}
