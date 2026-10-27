/// Price input state machine.
/// Rules: 5 digits + optional decimal; 3s continuous window;
/// >9999 => 1 decimal; >99999 => no decimal.
class PriceInputEngine {
  static const Duration continuousWindow = Duration(seconds: 3);
  static const int maxPriceDigits = 5;

  String _rawDigits = '';
  var _dotPressed = false;
  var _fracCount = 0;
  DateTime? _lastInputAt;

  String get displayText => formatDisplay(_rawDigits, _dotPressed, _fracCount);

  DateTime? get lastInputAt => _lastInputAt;

  bool get isEditing {
    final last = _lastInputAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) <= continuousWindow;
  }

  double get priceValue => double.tryParse(displayText) ?? 0.0;

  void clear() {
    _rawDigits = '';
    _dotPressed = false;
    _fracCount = 0;
    _lastInputAt = null;
  }

  bool inputDigit(String digit) {
    if (digit.length != 1 || digit.compareTo('0') < 0 || digit.compareTo('9') > 0) {
      return false;
    }
    _checkTimeout();
    if (_dotPressed) {
      final intDigits = _rawDigits.length - _fracCount;
      final remainDigits = maxPriceDigits - intDigits;
      final maxFrac = remainDigits <= 0 ? 0 : (remainDigits >= 2 ? 2 : 1);
      if (_fracCount >= maxFrac) {
        return false;
      }
      _rawDigits += digit;
      _fracCount += 1;
    } else {
      if (_rawDigits == '0') {
        _rawDigits = digit;
      } else {
        if (_rawDigits.length >= maxPriceDigits) {
          return false;
        }
        _rawDigits += digit;
      }
    }
    _lastInputAt = DateTime.now();
    _applyOverflowRules();
    return true;
  }

  bool inputDot() {
    _checkTimeout();
    if (_dotPressed) {
      _lastInputAt = DateTime.now();
      return false;
    }
    if (_rawDigits.isEmpty) {
      _rawDigits = '0';
    }
    if (_rawDigits.length >= maxPriceDigits) {
      _lastInputAt = DateTime.now();
      return false;
    }
    _dotPressed = true;
    _fracCount = 0;
    _lastInputAt = DateTime.now();
    return true;
  }

  int _intPartValue() {
    final intPartStr = _dotPressed
        ? _rawDigits.substring(0, _rawDigits.length - _fracCount)
        : _rawDigits;
    return int.tryParse(intPartStr.isEmpty ? '0' : intPartStr) ?? 0;
  }

  void _checkTimeout() {
    final last = _lastInputAt;
    if (last == null) {
      return;
    }
    if (DateTime.now().difference(last) > continuousWindow) {
      clear();
    }
  }

  void _applyOverflowRules() {
    final intPartStr = _dotPressed
        ? _rawDigits.substring(0, _rawDigits.length - _fracCount)
        : _rawDigits;
    final intDigits = intPartStr.length;
    final remainDigits = maxPriceDigits - intDigits;
    var maxFrac = remainDigits <= 0 ? 0 : (remainDigits >= 2 ? 2 : 1);
    if (_dotPressed && _fracCount > maxFrac) {
      _rawDigits = intPartStr + _rawDigits.substring(intPartStr.length, intPartStr.length + maxFrac);
      _fracCount = maxFrac;
      if (_fracCount == 0) {
        _dotPressed = false;
      }
    }
  }

  static String formatDisplay(String digits, bool dotPressed, int fracCount) {
    if (digits.isEmpty) {
      return '0';
    }
    String intPart;
    String fracPart;
    if (dotPressed) {
      final cut = digits.length - fracCount;
      intPart = cut <= 0 ? '0' : digits.substring(0, cut);
      fracPart = digits.substring(cut < 0 ? 0 : cut);
    } else {
      intPart = digits;
      fracPart = '';
    }
    if (!dotPressed) {
      return intPart;
    }
    if (fracPart.isEmpty) {
      return '$intPart.';
    }
    return '$intPart.$fracPart';
  }
}
