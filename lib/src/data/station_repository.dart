import 'package:flutter/material.dart';

import '../models/station.dart';

class StationRepository {
  const StationRepository();

  List<Station> get stations => const [
        Station(
          name: 'talkSPORT',
          slug: 'talksport',
          liveStreamUrl:
              'https://radio.talksport.com/stream?aw_0_1st.platform=website',
          accentColor: 0xFFFFED00,
        ),
        Station(
          name: 'talkSPORT 2',
          slug: 'talksport2',
          liveStreamUrl:
              'https://radio.talksport.com/stream2?aw_0_1st.platform=website',
          accentColor: 0xFFFFD500,
        ),
      ];

  Station bySlug(String slug) {
    return stations.firstWhere(
      (station) => station.slug == slug,
      orElse: () => stations.first,
    );
  }

  Color colorFor(Station station) => Color(station.accentColor);
}
