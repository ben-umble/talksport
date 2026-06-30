import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/now_playing.dart';
import '../models/playback_item.dart';
import '../models/schedule_day.dart';
import '../models/show.dart';
import '../models/station.dart';
import '../playback/playback_controller.dart';
import '../providers.dart';
import '../util/show_filters.dart';
import '../util/timecode.dart';

const _ink = Color(0xFF121316);
const _mutedInk = Color(0xFF69717D);
const _line = Color(0xFFE0E5EA);
const _paper = Color(0xFFF5F7FA);
const _yellow = Color(0xFFFFED00);
const _teal = Color(0xFF007A78);
const _orange = Color(0xFFE86F2A);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(selectedStationProvider);
    final stations = ref.watch(stationRepositoryProvider).stations;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            if (wide) {
              return Row(
                children: [
                  _SideRail(station: station, stations: stations),
                  Expanded(
                    child: _ContentScaffold(station: station, wide: true),
                  ),
                ],
              );
            }
            return _ContentScaffold(
              station: station,
              stations: stations,
              wide: false,
            );
          },
        ),
      ),
      bottomNavigationBar: const PlaybackDock(),
    );
  }
}

class _ContentScaffold extends ConsumerWidget {
  const _ContentScaffold({
    required this.station,
    required this.wide,
    this.stations = const [],
  });

  final Station station;
  final List<Station> stations;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1220),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 18, wide ? 28 : 16, 18),
              sliver: SliverList.list(
                children: [
                  if (!wide) ...[
                    _MobileTopBar(station: station, stations: stations),
                    const SizedBox(height: 18),
                  ] else
                    const _DesktopTopBar(),
                  const SizedBox(height: 18),
                  const _LiveHero(),
                  const SizedBox(height: 18),
                  const _CatchUpBrowser(),
                  const SizedBox(height: 132),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail({
    required this.station,
    required this.stations,
  });

  final Station station;
  final List<Station> stations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 260,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _yellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sports_soccer, color: _ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'talkSPORT',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            'Stations',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white60,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          for (final option in stations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StationRailButton(
                station: option,
                selected: option == station,
                onTap: () {
                  ref.read(selectedStationProvider.notifier).state = option;
                  ref.read(selectedDayNumberProvider.notifier).state = 0;
                },
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.headphones_rounded, color: _yellow),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Live and catch-up audio',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationRailButton extends StatelessWidget {
  const _StationRailButton({
    required this.station,
    required this.selected,
    required this.onTap,
  });

  final Station station;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _yellow : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _ink : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  station.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: selected ? _ink : Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends ConsumerWidget {
  const _DesktopTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(selectedStationProvider);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                station.name,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                DateFormat('EEEE d MMMM').format(DateTime.now()),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _mutedInk,
                    ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(scheduleProvider(station.slug));
            ref.invalidate(nowPlayingProvider(station.slug));
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _MobileTopBar extends ConsumerWidget {
  const _MobileTopBar({
    required this.station,
    required this.stations,
  });

  final Station station;
  final List<Station> stations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sports_soccer, color: _yellow),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'talkSPORT',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(scheduleProvider(station.slug));
                ref.invalidate(nowPlayingProvider(station.slug));
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedButton<Station>(
          segments: [
            for (final option in stations)
              ButtonSegment<Station>(
                value: option,
                label: Text(option.name),
              ),
          ],
          selected: {station},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            ref.read(selectedStationProvider.notifier).state = selection.first;
            ref.read(selectedDayNumberProvider.notifier).state = 0;
          },
        ),
      ],
    );
  }
}

class _LiveHero extends ConsumerWidget {
  const _LiveHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(selectedStationProvider);
    final nowPlaying = ref.watch(nowPlayingProvider(station.slug));
    return nowPlaying.when(
      data: (now) => _LiveHeroContent(station: station, nowPlaying: now),
      loading: () => const _StatusPanel(height: 260),
      error: (error, stackTrace) => _StatusPanel(
        height: 260,
        title: 'Live info unavailable',
        onRetry: () => ref.invalidate(nowPlayingProvider(station.slug)),
      ),
    );
  }
}

class _LiveHeroContent extends ConsumerWidget {
  const _LiveHeroContent({
    required this.station,
    required this.nowPlaying,
  });

  final Station station;
  final NowPlaying nowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final art = _Artwork(url: nowPlaying.thumbnailUrl, size: compact ? 112 : 144);
        final copy = Column(
          crossAxisAlignment:
              compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: compact ? WrapAlignment.center : WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                const _StatusBadge(label: 'LIVE', color: _yellow),
                _StatusBadge(
                  label: _formatRange(nowPlaying.startTime, nowPlaying.endTime),
                  color: Colors.white.withValues(alpha: 0.12),
                  foreground: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              nowPlaying.title,
              maxLines: compact ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: (compact
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
            ),
            if (nowPlaying.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                nowPlaying.description,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                ref
                    .read(playbackControllerProvider)
                    .playItem(PlaybackItem.live(station, nowPlaying));
              },
              style: FilledButton.styleFrom(
                backgroundColor: _yellow,
                foregroundColor: _ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Listen live on ${station.name}'),
            ),
          ],
        );

        return Container(
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black),
          ),
          child: compact
              ? Column(
                  children: [
                    art,
                    const SizedBox(height: 18),
                    copy,
                  ],
                )
              : Row(
                  children: [
                    art,
                    const SizedBox(width: 22),
                    Expanded(child: copy),
                  ],
                ),
        );
      },
    );
  }
}

class _CatchUpBrowser extends ConsumerWidget {
  const _CatchUpBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(selectedStationProvider);
    final schedule = ref.watch(scheduleProvider(station.slug));
    return schedule.when(
      data: (days) => _CatchUpContent(station: station, days: catchUpDays(days)),
      loading: () => const _StatusPanel(height: 460),
      error: (error, stackTrace) => _StatusPanel(
        height: 460,
        title: 'Catch-up unavailable',
        onRetry: () => ref.invalidate(scheduleProvider(station.slug)),
      ),
    );
  }
}

class _CatchUpContent extends ConsumerWidget {
  const _CatchUpContent({
    required this.station,
    required this.days,
  });

  final Station station;
  final List<ScheduleDay> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDayNumber = ref.watch(selectedDayNumberProvider);
    final query = ref.watch(searchQueryProvider);
    final selectedDay = days.firstWhere(
      (day) => day.dayNumber == selectedDayNumber,
      orElse: () => days.isEmpty
          ? const ScheduleDay(date: '', shows: [], itemId: '', dayNumber: 0)
          : days.first,
    );
    final shows = filterShows(selectedDay.shows, query);
    final availableCount = playableShows(selectedDay.shows).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Catch-up',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: _ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$availableCount available on ${_dayLabel(selectedDay)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: _mutedInk),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Refresh',
                      onPressed: () {
                        ref.invalidate(scheduleProvider(station.slug));
                        ref.invalidate(nowPlayingProvider(station.slug));
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SearchField(
                  onChanged: (value) =>
                      ref.read(searchQueryProvider.notifier).state = value,
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final day in days)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _DayChip(
                            day: day,
                            selected: day.dayNumber == selectedDay.dayNumber,
                            onTap: () {
                              ref.read(selectedDayNumberProvider.notifier).state =
                                  day.dayNumber;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          if (shows.isEmpty)
            const _EmptyState(title: 'No matching shows')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shows.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: _line),
              itemBuilder: (context, index) {
                return _ShowTile(station: station, show: shows[index]);
              },
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search shows',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: _paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final ScheduleDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = playableShows(day.shows).length;
    return Material(
      color: selected ? _ink : _paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _dayLabel(day),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? Colors.white : _ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? _yellow : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShowTile extends ConsumerWidget {
  const _ShowTile({
    required this.station,
    required this.show,
  });

  final Station station;
  final Show show;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration = show.recording?.durationValue;
    return InkWell(
      onTap: show.hasRecording
          ? () {
              ref
                  .read(playbackControllerProvider)
                  .playItem(PlaybackItem.catchUp(station, show));
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _Artwork(url: show.thumbnailUrl, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _formatRange(show.startTime, show.endTime),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: _mutedInk,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (show.hasRecording)
                        _TinyLabel(
                          icon: Icons.graphic_eq_rounded,
                          label: formatDuration(duration),
                          color: _teal,
                        )
                      else
                        const _TinyLabel(
                          icon: Icons.lock_clock_rounded,
                          label: 'Unavailable',
                          color: _mutedInk,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    show.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (show.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      show.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: _mutedInk),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _PlayGlyphButton(
              enabled: show.hasRecording,
              onPressed: () {
                ref
                    .read(playbackControllerProvider)
                    .playItem(PlaybackItem.catchUp(station, show));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackDock extends ConsumerWidget {
  const PlaybackDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(playbackControllerProvider);
    return ValueListenableBuilder<PlaybackItem?>(
      valueListenable: handler.currentItem,
      builder: (context, item, _) {
        if (item == null) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackStateStream,
          initialData: handler.playbackStateValue,
          builder: (context, snapshot) {
            final state = snapshot.data ?? handler.playbackStateValue;
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Material(
                      elevation: 18,
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showPlayerSheet(context, handler),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 760;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.isCatchUp)
                                    _DockSeekBar(handler: handler, item: item),
                                  const SizedBox(height: 8),
                                  compact
                                      ? _CompactDockRow(
                                          handler: handler,
                                          item: item,
                                          state: state,
                                        )
                                      : _WideDockRow(
                                          handler: handler,
                                          item: item,
                                          state: state,
                                        ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WideDockRow extends StatelessWidget {
  const _WideDockRow({
    required this.handler,
    required this.item,
    required this.state,
  });

  final PlaybackController handler;
  final PlaybackItem item;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Artwork(url: item.imageUrl, size: 52),
        const SizedBox(width: 14),
        Expanded(child: _NowPlayingText(item: item)),
        _TransportCluster(handler: handler, item: item, state: state),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Open player',
          onPressed: () => _showPlayerSheet(context, handler),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
      ],
    );
  }
}

class _CompactDockRow extends StatelessWidget {
  const _CompactDockRow({
    required this.handler,
    required this.item,
    required this.state,
  });

  final PlaybackController handler;
  final PlaybackItem item;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Artwork(url: item.imageUrl, size: 46),
        const SizedBox(width: 12),
        Expanded(child: _NowPlayingText(item: item)),
        _RoundPlayButton(
          playing: state.playing,
          onPressed: state.playing ? handler.pause : handler.play,
          size: 46,
        ),
      ],
    );
  }
}

class _NowPlayingText extends StatelessWidget {
  const _NowPlayingText({required this.item});

  final PlaybackItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          item.isLive ? 'Live on ${item.stationName}' : item.stationName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _mutedInk,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _TransportCluster extends StatelessWidget {
  const _TransportCluster({
    required this.handler,
    required this.item,
    required this.state,
  });

  final PlaybackController handler;
  final PlaybackItem item;
  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.isCatchUp)
          _SkipTransportButton(
            tooltip: 'Back 15 seconds',
            icon: Icons.fast_rewind_rounded,
            onPressed: handler.rewind,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _RoundPlayButton(
            playing: state.playing,
            onPressed: state.playing ? handler.pause : handler.play,
          ),
        ),
        if (item.isCatchUp)
          _SkipTransportButton(
            tooltip: 'Forward 15 seconds',
            icon: Icons.fast_forward_rounded,
            onPressed: handler.fastForward,
          ),
      ],
    );
  }
}

class _DockSeekBar extends StatelessWidget {
  const _DockSeekBar({
    required this.handler,
    required this.item,
  });

  final PlaybackController handler;
  final PlaybackItem item;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      initialData: handler.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = handler.duration ?? item.duration ?? Duration.zero;
        return Row(
          children: [
            Text(
              formatDuration(position),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _mutedInk,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Expanded(
              child: _SeekSlider(
                position: position,
                duration: duration,
                onChanged: (next) => handler.seek(next),
                compact: true,
              ),
            ),
            Text(
              formatDuration(duration),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _mutedInk,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _ExpandedPlayer extends StatelessWidget {
  const _ExpandedPlayer({required this.handler});

  final PlaybackController handler;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackItem?>(
      valueListenable: handler.currentItem,
      builder: (context, item, _) {
        if (item == null) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackStateStream,
          initialData: handler.playbackStateValue,
          builder: (context, snapshot) {
            final state = snapshot.data ?? handler.playbackStateValue;
            return Padding(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 8,
                bottom: 22 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Artwork(url: item.imageUrl, size: 154),
                    const SizedBox(height: 20),
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: _ink,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _mutedInk,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 22),
                    if (item.isCatchUp)
                      _ExpandedTimeline(handler: handler, item: item)
                    else
                      const _StatusBadge(label: 'LIVE STREAM', color: _yellow),
                    const SizedBox(height: 22),
                    _TransportCluster(handler: handler, item: item, state: state),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ExpandedTimeline extends StatelessWidget {
  const _ExpandedTimeline({
    required this.handler,
    required this.item,
  });

  final PlaybackController handler;
  final PlaybackItem item;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      initialData: handler.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = handler.duration ?? item.duration ?? Duration.zero;
        final remaining =
            position >= duration ? Duration.zero : duration - position;
        return Column(
          children: [
            _SeekSlider(
              position: position,
              duration: duration,
              onChanged: handler.seek,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  formatDuration(position),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                ),
                const Spacer(),
                Text(
                  '-${formatDuration(remaining)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _mutedInk,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _TimeJumpField(
              duration: duration,
              onJump: handler.seek,
            ),
          ],
        );
      },
    );
  }
}

class _SeekSlider extends StatelessWidget {
  const _SeekSlider({
    required this.position,
    required this.duration,
    required this.onChanged,
    this.compact = false,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds.toDouble().clamp(1, double.infinity);
    final value = position.inMilliseconds.toDouble().clamp(0, max);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: compact ? 4 : 8,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: compact ? 7 : 10),
        overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 16 : 22),
        activeTrackColor: _orange,
        inactiveTrackColor: _line,
        thumbColor: _orange,
      ),
      child: Slider(
        value: value.toDouble(),
        max: max.toDouble(),
        onChanged: duration == Duration.zero
            ? null
            : (next) => onChanged(Duration(milliseconds: next.round())),
      ),
    );
  }
}

class _TimeJumpField extends StatefulWidget {
  const _TimeJumpField({
    required this.duration,
    required this.onJump,
  });

  final Duration duration;
  final ValueChanged<Duration> onJump;

  @override
  State<_TimeJumpField> createState() => _TimeJumpFieldState();
}

class _TimeJumpFieldState extends State<_TimeJumpField> {
  final _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.datetime,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
      ],
      onSubmitted: (_) => _jump(),
      decoration: InputDecoration(
        labelText: 'Jump to time',
        hintText: '1:23:45',
        errorText: _invalid ? 'Use seconds, mm:ss, or h:mm:ss' : null,
        prefixIcon: const Icon(Icons.timer_outlined),
        suffixIcon: IconButton(
          tooltip: 'Jump',
          onPressed: _jump,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _jump() {
    final target = parseTimecode(_controller.text, max: widget.duration);
    setState(() => _invalid = target == null);
    if (target != null) {
      widget.onJump(target);
    }
  }
}

class _RoundPlayButton extends StatelessWidget {
  const _RoundPlayButton({
    required this.playing,
    required this.onPressed,
    this.size = 56,
  });

  final bool playing;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        tooltip: playing ? 'Pause' : 'Play',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        iconSize: size >= 56 ? 32 : 28,
        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}

class _SkipTransportButton extends StatelessWidget {
  const _SkipTransportButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _paper,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: _ink),
                Text(
                  '15s',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayGlyphButton extends StatelessWidget {
  const _PlayGlyphButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: enabled ? 'Listen' : 'Not available',
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _paper,
        disabledForegroundColor: _mutedInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.play_arrow_rounded),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.size,
  });

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: _ink,
        child: imageUrl == null || imageUrl.isEmpty
            ? const Icon(Icons.radio_rounded, color: _yellow)
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.radio_rounded, color: _yellow),
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    this.foreground = _ink,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _TinyLabel extends StatelessWidget {
  const _TinyLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.height,
    this.title,
    this.onRetry,
  });

  final double height;
  final String? title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: title == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 40, color: _mutedInk),
                const SizedBox(height: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (onRetry != null) ...[
                  const SizedBox(height: 10),
                  IconButton.filledTonal(
                    tooltip: 'Retry',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: Center(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _mutedInk,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

void _showPlayerSheet(BuildContext context, PlaybackController handler) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (context) => Center(
      child: SingleChildScrollView(
        child: _ExpandedPlayer(handler: handler),
      ),
    ),
  );
}

String _formatRange(DateTime start, DateTime end) {
  final format = DateFormat('h:mm a');
  return '${format.format(start)} - ${format.format(end)}';
}

String _dayLabel(ScheduleDay day) {
  if (day.dayNumber == 0) {
    return 'Today';
  }
  if (day.dayNumber == -1) {
    return 'Yesterday';
  }
  final date = DateTime.tryParse(day.date);
  if (date == null) {
    return day.date;
  }
  return DateFormat('EEE d MMM').format(date);
}
