import 'dart:typed_data';

enum LiveAudioFormat { mp3, aacAdts }

class LiveAudioFrame {
  const LiveAudioFrame({
    required this.bytes,
    required this.sampleRate,
    required this.sampleCount,
  });

  final Uint8List bytes;
  final int sampleRate;
  final int sampleCount;
}

class LiveAudioFrameParser {
  LiveAudioFrameParser(this.format);

  final LiveAudioFormat format;
  Uint8List _pending = Uint8List(0);

  List<LiveAudioFrame> add(List<int> chunk) {
    if (chunk.isEmpty) {
      return const [];
    }

    final bytes = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    final frames = <LiveAudioFrame>[];
    var cursor = 0;

    while (cursor + _minimumHeaderLength <= bytes.length) {
      final header = _parseHeader(bytes, cursor);
      if (header == null) {
        cursor += 1;
        continue;
      }

      final frameEnd = cursor + header.length;
      if (frameEnd > bytes.length) {
        break;
      }

      if (frameEnd + _minimumHeaderLength > bytes.length) {
        break;
      }
      if (_parseHeader(bytes, frameEnd) == null) {
        cursor += 1;
        continue;
      }

      frames.add(
        LiveAudioFrame(
          bytes: Uint8List.sublistView(bytes, cursor, frameEnd),
          sampleRate: header.sampleRate,
          sampleCount: header.sampleCount,
        ),
      );
      cursor = frameEnd;
    }

    final remaining = bytes.length - cursor;
    if (remaining <= 0) {
      _pending = Uint8List(0);
    } else {
      final keepFrom = remaining > _maximumPendingBytes
          ? bytes.length - _maximumPendingBytes
          : cursor;
      _pending = Uint8List.sublistView(bytes, keepFrom);
    }
    return frames;
  }

  void reset() {
    _pending = Uint8List(0);
  }

  int get _minimumHeaderLength => format == LiveAudioFormat.mp3 ? 4 : 7;

  _FrameHeader? _parseHeader(Uint8List bytes, int offset) {
    return switch (format) {
      LiveAudioFormat.mp3 => _parseMp3Header(bytes, offset),
      LiveAudioFormat.aacAdts => _parseAdtsHeader(bytes, offset),
    };
  }

  static _FrameHeader? _parseMp3Header(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length ||
        bytes[offset] != 0xff ||
        (bytes[offset + 1] & 0xe0) != 0xe0) {
      return null;
    }

    final versionBits = (bytes[offset + 1] >> 3) & 0x03;
    final layerBits = (bytes[offset + 1] >> 1) & 0x03;
    final bitrateIndex = (bytes[offset + 2] >> 4) & 0x0f;
    final sampleRateIndex = (bytes[offset + 2] >> 2) & 0x03;
    final padding = (bytes[offset + 2] >> 1) & 0x01;
    if (versionBits == 1 ||
        layerBits != 1 ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        sampleRateIndex == 3) {
      return null;
    }

    final isMpeg1 = versionBits == 3;
    final bitrate = (isMpeg1
        ? _mpeg1Layer3Rates
        : _mpeg2Layer3Rates)[bitrateIndex];
    var sampleRate = _mpeg1SampleRates[sampleRateIndex];
    if (versionBits == 2) {
      sampleRate ~/= 2;
    } else if (versionBits == 0) {
      sampleRate ~/= 4;
    }

    final coefficient = isMpeg1 ? 144 : 72;
    final length = (coefficient * bitrate * 1000 ~/ sampleRate) + padding;
    if (length < 24 || length > _maximumFrameLength) {
      return null;
    }

    return _FrameHeader(
      length: length,
      sampleRate: sampleRate,
      sampleCount: isMpeg1 ? 1152 : 576,
    );
  }

  static _FrameHeader? _parseAdtsHeader(Uint8List bytes, int offset) {
    if (offset + 7 > bytes.length ||
        bytes[offset] != 0xff ||
        (bytes[offset + 1] & 0xf6) != 0xf0) {
      return null;
    }

    final sampleRateIndex = (bytes[offset + 2] >> 2) & 0x0f;
    if (sampleRateIndex >= _aacSampleRates.length) {
      return null;
    }
    final sampleRate = _aacSampleRates[sampleRateIndex];
    if (sampleRate == 0) {
      return null;
    }

    final length =
        ((bytes[offset + 3] & 0x03) << 11) |
        (bytes[offset + 4] << 3) |
        ((bytes[offset + 5] & 0xe0) >> 5);
    final headerLength = (bytes[offset + 1] & 0x01) == 1 ? 7 : 9;
    if (length < headerLength || length > _maximumFrameLength) {
      return null;
    }

    final rawDataBlocks = bytes[offset + 6] & 0x03;
    return _FrameHeader(
      length: length,
      sampleRate: sampleRate,
      sampleCount: 1024 * (rawDataBlocks + 1),
    );
  }

  static const _maximumFrameLength = 8192;
  static const _maximumPendingBytes = _maximumFrameLength * 2;
  static const _mpeg1SampleRates = [44100, 48000, 32000];
  static const _mpeg1Layer3Rates = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
    0,
  ];
  static const _mpeg2Layer3Rates = [
    0,
    8,
    16,
    24,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
    0,
  ];
  static const _aacSampleRates = [
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000,
    7350,
    0,
    0,
    0,
  ];
}

class _FrameHeader {
  const _FrameHeader({
    required this.length,
    required this.sampleRate,
    required this.sampleCount,
  });

  final int length;
  final int sampleRate;
  final int sampleCount;
}
