Map<String, String> stringMapFromJson(Object? json) {
  if (json is! Map) {
    return const {};
  }
  return json.map((key, value) => MapEntry('$key', value?.toString() ?? ''));
}

DateTime dateTimeFromJson(String value) => DateTime.parse(value);

String dateTimeToJson(DateTime value) => value.toUtc().toIso8601String();
