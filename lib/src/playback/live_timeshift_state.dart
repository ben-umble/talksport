import 'dart:math';

import 'package:flutter/foundation.dart';

enum LiveTimeshiftPhase { idle, connecting, ready, reconnecting, failed }

@immutable
class LiveTimeshiftState {
  const LiveTimeshiftState({
    required this.phase,
    required this.bufferStart,
    required this.liveEdge,
    required this.playbackPosition,
    this.errorMessage,
  });

  const LiveTimeshiftState.idle()
    : phase = LiveTimeshiftPhase.idle,
      bufferStart = Duration.zero,
      liveEdge = Duration.zero,
      playbackPosition = Duration.zero,
      errorMessage = null;

  final LiveTimeshiftPhase phase;
  final Duration bufferStart;
  final Duration liveEdge;
  final Duration playbackPosition;
  final String? errorMessage;

  Duration get bufferedDuration => _nonNegative(liveEdge - bufferStart);

  Duration get behindLive => _nonNegative(liveEdge - playbackPosition);

  bool get isActive => phase != LiveTimeshiftPhase.idle;

  bool get isRecording => phase == LiveTimeshiftPhase.ready;

  bool get isRecovering => phase == LiveTimeshiftPhase.reconnecting;

  bool get isAtLiveEdge => behindLive <= const Duration(seconds: 3);

  bool get canSeek =>
      isActive && bufferedDuration >= const Duration(seconds: 2);

  bool get canGoLive => canSeek && !isAtLiveEdge;

  LiveTimeshiftState copyWith({
    LiveTimeshiftPhase? phase,
    Duration? bufferStart,
    Duration? liveEdge,
    Duration? playbackPosition,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LiveTimeshiftState(
      phase: phase ?? this.phase,
      bufferStart: bufferStart ?? this.bufferStart,
      liveEdge: liveEdge ?? this.liveEdge,
      playbackPosition: playbackPosition ?? this.playbackPosition,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  static Duration _nonNegative(Duration value) {
    return value.isNegative ? Duration.zero : value;
  }
}

/// Turns packet-based live-edge observations into a steady presentation clock.
class LiveEdgePresentationClock {
  LiveEdgePresentationClock({
    this.maximumExtrapolation = const Duration(seconds: 3),
    this.hardForwardReset = const Duration(seconds: 5),
  });

  final Duration maximumExtrapolation;
  final Duration hardForwardReset;
  Duration? _presentedEdge;
  DateTime? _presentedAt;
  LiveTimeshiftPhase _phase = LiveTimeshiftPhase.idle;
  bool _wasAdvancing = false;

  Duration project({
    required Duration observedEdge,
    required DateTime? observedAt,
    required LiveTimeshiftPhase phase,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final observationAge = observedAt == null
        ? Duration.zero
        : _nonNegative(now.difference(observedAt));
    final cappedAge = Duration(
      microseconds: min(
        observationAge.inMicroseconds,
        maximumExtrapolation.inMicroseconds,
      ),
    );
    final observationIsFresh =
        phase == LiveTimeshiftPhase.ready &&
        observationAge <= maximumExtrapolation;
    final measuredEdge = phase == LiveTimeshiftPhase.ready
        ? observedEdge + cappedAge
        : observedEdge;
    final current = _presentedEdge;
    final previousAt = _presentedAt;

    if (current == null ||
        previousAt == null ||
        phase == LiveTimeshiftPhase.idle ||
        (_phase == LiveTimeshiftPhase.connecting &&
            phase == LiveTimeshiftPhase.ready)) {
      _setAnchor(measuredEdge, now, phase, observationIsFresh);
      return measuredEdge;
    }

    final elapsed = _nonNegative(now.difference(previousAt));
    final expectedEdge = current + (_wasAdvancing ? elapsed : Duration.zero);
    var presentedEdge = expectedEdge;

    if (phase == LiveTimeshiftPhase.ready) {
      final errorMicros =
          measuredEdge.inMicroseconds - expectedEdge.inMicroseconds;
      if (errorMicros > hardForwardReset.inMicroseconds) {
        presentedEdge = measuredEdge;
      } else {
        final correctionLimit = elapsed.inMicroseconds ~/ 4;
        final correction = errorMicros.clamp(-correctionLimit, correctionLimit);
        presentedEdge = Duration(
          microseconds: expectedEdge.inMicroseconds + correction,
        );
      }
    }

    if (presentedEdge < current) {
      presentedEdge = current;
    }
    _setAnchor(presentedEdge, now, phase, observationIsFresh);
    return presentedEdge;
  }

  void reset() {
    _presentedEdge = null;
    _presentedAt = null;
    _phase = LiveTimeshiftPhase.idle;
    _wasAdvancing = false;
  }

  void _setAnchor(
    Duration edge,
    DateTime at,
    LiveTimeshiftPhase phase,
    bool advancing,
  ) {
    _presentedEdge = edge;
    _presentedAt = at;
    _phase = phase;
    _wasAdvancing = advancing;
  }

  static Duration _nonNegative(Duration value) {
    return value.isNegative ? Duration.zero : value;
  }
}
