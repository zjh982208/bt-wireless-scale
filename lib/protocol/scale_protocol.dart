import 'dart:convert';
import 'dart:typed_data';

/// Parsed uplink frame (42 bytes).
class ScaleFrameData {
  ScaleFrameData({
    required this.flag,
    required this.sign,
    required this.weightText,
    required this.unit,
    required this.priceText,
    required this.totalText,
    required this.totalAmountText,
    required this.timesText,
  });

  final String flag; // S stable / U unstable / F fault
  final String sign; // space positive / '-' negative
  final String weightText;
  final String unit;
  final String priceText;
  final String totalText;
  final String totalAmountText;
  final String timesText;

  bool get isStable => flag == 'S';
  bool get isOverload => flag == 'F';
  bool get isNegative => sign == '-';

  String get displayWeight {
    final v = weightText.trim();
    if (isNegative && !v.startsWith('-')) {
      return '-$v';
    }
    return v;
  }
}

/// SD wireless scale custom protocol (not Topscale OS2X).
class ScaleProtocol {
  static const int frameLen = 42;
  static const int head1 = 0x01;
  static const int head2 = 0x02;
  static const int tail1 = 0x03;
  static const int tail2 = 0x04;

  static const int cmdStx = 0x3C; // '<'
  static const int cmdEtx1 = 0x3E; // '>'
  static const int cmdEtx2 = 0x09;

  static int xorChecksum(List<int> bytes, int start, int endExclusive) {
    var sum = 0;
    for (var i = start; i < endExclusive; i++) {
      sum ^= (bytes[i] & 0xFF);
    }
    return sum & 0xFF;
  }

  static String padAscii(String raw, int width, {String pad = '0'}) {
    var text = raw.trim();
    if (text.length > width) {
      text = text.substring(text.length - width);
    }
    return text.padLeft(width, pad);
  }

  /// Format price to 6 ASCII chars with at most 5 digits.
  /// Examples: 1.23 -> 001.23, 1234.5 -> 1234.5, 12345 -> 12345.
  static String formatPrice6(num price) {
    if (price < 0) {
      price = 0;
    }
    if (price > 99999) {
      price = 99999;
    }
    final rounded = ((price * 100).round()) / 100.0;
    String text = rounded.toStringAsFixed(2);
    var parts = text.split('.');
    var intPart = parts[0];
    var fracPart = parts.length > 1 ? parts[1] : '';
    if (intPart.length >= 5) {
      text = '${intPart.substring(0, 5)}.';
    } else if (intPart.length == 4) {
      text = '$intPart.${fracPart.isEmpty ? '0' : fracPart[0]}';
    } else {
      final fp = fracPart.padRight(2, '0');
      text = '$intPart.${fp.substring(0, 2)}';
    }
    return padAscii(text, 6);
  }

  static ScaleFrameData? parseUplink(List<int> frame) {
    if (frame.length != frameLen) {
      return null;
    }
    if (frame[0] != head1 || frame[1] != head2) {
      return null;
    }
    if (frame[40] != tail1 || frame[41] != tail2) {
      return null;
    }
    final expect39 = xorChecksum(frame, 0, 39);
    final actual = frame[39] & 0xFF;
    if (actual != expect39) {
      return null;
    }
    String take(int start, int len) {
      return ascii.decode(frame.sublist(start, start + len), allowInvalid: true);
    }

    return ScaleFrameData(
      flag: take(6, 1),
      sign: take(7, 1),
      weightText: take(8, 6),
      unit: take(14, 2),
      priceText: take(16, 6),
      totalText: take(22, 7),
      totalAmountText: take(29, 7),
      timesText: take(36, 3),
    );
  }

  /// Extract complete frames from stream buffer (sticky/half packet safe).
  static List<ScaleFrameData> extractFrames(List<int> buffer) {
    final out = <ScaleFrameData>[];
    var i = 0;
    while (i + frameLen <= buffer.length) {
      if (buffer[i] == head1 && buffer[i + 1] == head2) {
        final candidate = buffer.sublist(i, i + frameLen);
        final parsed = parseUplink(candidate);
        if (parsed != null) {
          out.add(parsed);
          i += frameLen;
          continue;
        }
      }
      i += 1;
    }
    if (i > 0) {
      buffer.removeRange(0, i);
    } else if (buffer.length > frameLen * 4) {
      buffer.removeRange(0, buffer.length - frameLen);
    }
    return out;
  }

  static Uint8List buildTareCmd() => _buildSimpleCmd([0x54, 0x4B]); // TK
  static Uint8List buildZeroCmd() => _buildSimpleCmd([0x5A, 0x4B]); // ZK
  static Uint8List buildAddCmd() => _buildSimpleCmd([0x41, 0x44]); // AD
  static Uint8List buildClearAccCmd() => _buildSimpleCmd([0x41, 0x43]); // AC
  static Uint8List buildModeDisplayCmd() => _buildSimpleCmd([0x4D, 0x44]); // MD scale display
  static Uint8List buildModeOperateCmd() => _buildSimpleCmd([0x4D, 0x4F]); // MO scale operate

  static Uint8List _buildSimpleCmd(List<int> cmd) {
    return Uint8List.fromList([cmdStx, cmd[0], cmd[1], cmdEtx1, cmdEtx2]);
  }

  /// Price downlink 15 bytes.
  /// CheckSum = XOR of offset 0..11
  static Uint8List buildPriceFrame(num price) {
    final price6 = formatPrice6(price);
    final bytes = <int>[
      head1,
      head2,
      ...'015'.codeUnits,
      'P'.codeUnitAt(0),
      ...price6.codeUnits,
      0x00,
      tail1,
      tail2,
    ];
    bytes[12] = xorChecksum(bytes, 0, 12);
    return Uint8List.fromList(bytes);
  }
}
