class Station {
  const Station({
    required this.name,
    required this.slug,
    required this.liveStreamUrl,
    required this.accentColor,
  });

  final String name;
  final String slug;
  final String liveStreamUrl;
  final int accentColor;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Station &&
            runtimeType == other.runtimeType &&
            slug == other.slug;
  }

  @override
  int get hashCode => slug.hashCode;
}
