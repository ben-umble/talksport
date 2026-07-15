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
