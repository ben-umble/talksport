import '../models/schedule_day.dart';
import '../models/show.dart';

List<ScheduleDay> catchUpDays(List<ScheduleDay> days) {
  return days.where((day) => day.dayNumber >= -7 && day.dayNumber <= 0).toList()
    ..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));
}

List<Show> filterShows(List<Show> shows, String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return shows;
  }
  return shows.where((show) {
    return show.title.toLowerCase().contains(trimmed) ||
        show.programmeTitle.toLowerCase().contains(trimmed) ||
        show.description.toLowerCase().contains(trimmed);
  }).toList();
}

List<Show> playableShows(List<Show> shows) {
  return shows.where((show) => show.hasRecording).toList();
}
