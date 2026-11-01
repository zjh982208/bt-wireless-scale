/// Price input state machine.
/// At most 5 digits. The next digit or dot after that restarts from the ones place.
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

  bool _overLimit() {
    return _rawDigits.length >= maxPriceDigits || priceValue > 99999;
  }

  void _restartForNewInput() {
    _rawDigits = '';
    _dotPressed = false;
    _fracCount = 0;
  }

  bool inputDigit(String digit) {
    if (digit.length != 1 || digit.compareTo('0') < 0 || digit.compareTo('9') > 0) {
      return false;
    }
    _checkTimeout();
    // 已有5位或大于99999时，本次按键清掉原单价，新数字从个位开始。
    if (_overLimit()) {
      _restartForNewInput();
    }
    if (_dotPressed) {
      final intDigits = _rawDigits.length - _fracCount;
      final remainDigits = maxPriceDigits - intDigits;
      final maxFrac = remainDigits <= 0 ? 0 : (remainDigits >= 2 ? 2 : 1);
      if (_fracCount >= maxFrac) {
        _lastInputAt = DateTime.now(); // 小数位已满但未超过5位，保持当前单价并继续响应。 //
        return true;
      } else {
        _rawDigits += digit;
        _fracCount += 1;
      }
    } else {
      if (_rawDigits == '0') {
        _rawDigits = digit;
      } else {
        _rawDigits += digit;
      }
    }
    _lastInputAt = DateTime.now();
    _applyOverflowRules();
    return true;
  }

  bool inputDot() {
    _checkTimeout();
    // 已有5位或大于99999时，小数点也重新从0.开始。
    if (_overLimit()) {
      _restartForNewInput();
    }
    if (_dotPressed) {
      _lastInputAt = DateTime.now();
      return true;
    }
    if (_rawDigits.isEmpty) {
      _rawDigits = '0';
    }
    _dotPressed = true;
    _fracCount = 0;
    _lastInputAt = DateTime.now();
    return true;
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
