import 'package:flutter/material.dart';

import '../app/scale_controller.dart';
import '../ble/kt6368_uart.dart';
import 'scan_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final ScaleController controller;

  Future<void> _openScan(BuildContext context) async {
    if (!controller.canOpenScan) {
      return;
    }
    await controller.enterManualSelectMode();
    controller.lockScanOpen();
    final BleDeviceItem? selected = await Navigator.of(context).push<BleDeviceItem>(
      MaterialPageRoute(
        builder: (_) => ScanPage(controller: controller),
      ),
    );
    if (selected != null) {
      await controller.connectDevice(selected);
      return;
    }
    controller.exitManualSelectMode();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final operate = controller.workMode == AppWorkMode.operate;
        final connected = controller.connState == ConnState.connected;
        final scanEnabled = controller.canOpenScan;
        final isChinese = controller.isChinese;
        return Scaffold(
          backgroundColor: const Color(0xFFE9EDF2),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  _TopBar(
                    titleText: isChinese ? 'SD\u65e0\u7ebf\u79e4' : 'SD Wireless Scale',
                    operate: operate,
                    connected: connected,
                    scanEnabled: scanEnabled,
                    languageText: isChinese ? '\u4e2d' : 'EN',
                    onToggleMode: controller.toggleWorkMode,
                    onScan: scanEnabled ? () => _openScan(context) : null,
                    onToggleLanguage: controller.toggleLanguage,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: connected ? const Color(0xFF185ABC) : const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DisplayCard(
                    label: isChinese ? '\u91cd\u91cf' : 'Weight',
                    unit: controller.unitText,
                    value: controller.weightText,
                    valueColor: const Color(0xFF185ABC),
                    valueSize: 30,
                  ),
                  _DisplayCard(
                    label: isChinese ? '\u5355\u4ef7' : 'Price',
                    unit: isChinese ? '\u5143/${controller.unitText}' : '${controller.unitText} price',
                    value: operate && controller.priceEngine.isEditing
                        ? controller.priceEngine.displayText
                        : controller.priceText,
                  ),
                  _DisplayCard(
                    label: isChinese ? '\u603b\u4ef7' : 'Total',
                    unit: isChinese ? '\u5143' : 'CNY',
                    value: controller.totalText,
                    valueColor: const Color(0xFFCC5F00),
                    valueSize: 26,
                  ),
                  _CumulativeCard(
                    titleWeight: isChinese ? '\u7d2f\u8ba1\u91cd\u91cf' : 'Accum Weight',
                    titleTimes: isChinese ? '\u7d2f\u8ba1\u6b21\u6570' : 'Accum Times',
                    titleAmount: isChinese ? '\u7d2f\u8ba1\u91d1\u989d' : 'Accum Amount',
                    detailTitle: isChinese ? '\u672c\u6b21\u7d2f\u8ba1\u660e\u7ec6' : 'Accumulation Details',
                    seqTitle: isChinese ? '\u5e8f\u53f7' : 'No.',
                    rowWeightTitle: isChinese ? '\u91cd\u91cf' : 'Weight',
                    rowPriceTitle: isChinese ? '\u5355\u4ef7' : 'Price',
                    rowAmountTitle: isChinese ? '\u91d1\u989d' : 'Amount',
                    weight: controller.cumulativeWeightText,
                    amount: controller.totalAmountText,
                    times: controller.timesText,
                    records: controller.cumulativeRecords,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _Keypad(
                      enabled: operate,
                      zeroLabel: isChinese ? '\u7f6e\u96f6' : 'Zero',
                      tareLabel: isChinese ? '\u53bb\u76ae' : 'Tare',
                      clearLabel: isChinese ? '\u6e05\u9664' : 'Clear',
                      addLabel: isChinese ? '\u7d2f\u8ba1' : 'Add',
                      clearAccLabel: isChinese ? '\u7d2f\u6e05' : 'ClrAcc',
                      onDigit: controller.onDigit,
                      onDot: controller.onDot,
                      onZero: controller.onZero,
                      onTare: controller.onTare,
                      onClear: controller.onClearPrice,
                      onAdd: controller.onAdd,
                      onClearAcc: controller.onClearAcc,
                    ),
                  ),
                  if (!operate)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Text(
                        isChinese
                            ? '\u5f53\u524d\u4e3a\u663e\u793a\u6a21\u5f0f\uff1a\u4ec5\u663e\u793a\u79e4\u6570\u636e\uff0c\u952e\u76d8\u4e0d\u53ef\u64cd\u4f5c\n\u70b9\u51fb\u53f3\u4e0a\u89d2\u56fe\u6807\u53ef\u5207\u6362\u5230\u64cd\u4f5c\u6a21\u5f0f'
                            : 'Display mode: scale data only, keypad disabled.\nTap top-right icon to switch to operate mode',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF999999),
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        isChinese
                            ? '\u70b9\u51fb\u53f3\u4e0a\u89d2\u84dd\u7259\u56fe\u6807\u626b\u63cf\u5e76\u8fde\u63a5\u84dd\u7259\u79e4'
                            : 'Tap Bluetooth icon to scan and connect scale',
                        style: TextStyle(fontSize: 11, color: Color(0xFFBBBBBB)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.titleText,
    required this.operate,
    required this.connected,
    required this.scanEnabled,
    required this.languageText,
    required this.onToggleMode,
    required this.onScan,
    required this.onToggleLanguage,
  });

  final String titleText;
  final bool operate;
  final bool connected;
  final bool scanEnabled;
  final String languageText;
  final VoidCallback onToggleMode;
  final VoidCallback? onScan;
  final VoidCallback onToggleLanguage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            titleText,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        _IconBtn(
          color: const Color(0xFFE8F0FE),
          onTap: onToggleLanguage,
          child: Text(
            languageText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF185ABC),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _IconBtn(
          color: operate ? const Color(0xFFDCE7FB) : const Color(0xFFE5E7EB),
          onTap: onToggleMode,
          child: Icon(
            operate ? Icons.touch_app : Icons.visibility,
            size: 20,
            color: operate ? const Color(0xFF185ABC) : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 8),
        _IconBtn(
          color: scanEnabled ? const Color(0xFFDCE7FB) : const Color(0xFFE5E7EB),
          onTap: onScan,
          child: Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth,
            size: 20,
            color: scanEnabled ? const Color(0xFF185ABC) : const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.color, required this.onTap, required this.child});

  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 36, height: 36, child: Center(child: child)),
      ),
    );
  }
}

class _DisplayCard extends StatelessWidget {
  const _DisplayCard({
    required this.label,
    required this.unit,
    required this.value,
    this.valueColor = const Color(0xFF1A1A1A),
    this.valueSize = 28,
  });

  final String label;
  final String unit;
  final String value;
  final Color valueColor;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9DEE6)),
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.w700,
                color: valueColor,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CumulativeCard extends StatefulWidget {
  const _CumulativeCard({
    required this.titleWeight,
    required this.titleTimes,
    required this.titleAmount,
    required this.detailTitle,
    required this.seqTitle,
    required this.rowWeightTitle,
    required this.rowPriceTitle,
    required this.rowAmountTitle,
    required this.weight,
    required this.amount,
    required this.times,
    required this.records,
  });

  final String titleWeight;
  final String titleTimes;
  final String titleAmount;
  final String detailTitle;
  final String seqTitle;
  final String rowWeightTitle;
  final String rowPriceTitle;
  final String rowAmountTitle;
  final String weight;
  final String amount;
  final String times;
  final List<CumulativeRecord> records;

  @override
  State<_CumulativeCard> createState() => _CumulativeCardState();
}

class _CumulativeCardState extends State<_CumulativeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFE0A3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CumItem(label: widget.titleWeight, value: widget.weight),
                ),
                Container(width: 1, height: 32, color: const Color(0xFFFFE0A3)),
                Expanded(
                  child: _CumItem(label: widget.titleTimes, value: widget.times),
                ),
                Container(width: 1, height: 32, color: const Color(0xFFFFE0A3)),
                Expanded(
                  child: _CumItem(label: widget.titleAmount, value: widget.amount),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: const Color(0xFFB85C00),
                ),
              ],
            ),
            if (_expanded) const SizedBox(height: 10),
            if (_expanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE9BA)),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.detailTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF996600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _RecordRow(
                      seq: widget.seqTitle,
                      weight: widget.rowWeightTitle,
                      price: widget.rowPriceTitle,
                      amount: widget.rowAmountTitle,
                      header: true,
                    ),
                    const SizedBox(height: 2),
                    if (widget.records.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          '-',
                          style: TextStyle(fontSize: 13, color: Color(0xFFB3A06F)),
                        ),
                      )
                    else
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          itemCount: widget.records.length,
                          itemBuilder: (context, index) {
                            final e = widget.records[index];
                            return _RecordRow(
                              seq: e.index.toString(),
                              weight: e.weight,
                              price: e.price,
                              amount: e.amount,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CumItem extends StatelessWidget {
  const _CumItem({required this.label, required this.value, this.valueSize = 18});

  final String label;
  final String value;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF996600))),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB85C00),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.seq,
    required this.weight,
    required this.price,
    required this.amount,
    this.header = false,
  });

  final String seq;
  final String weight;
  final String price;
  final String amount;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final color = header ? const Color(0xFF9A7B3D) : const Color(0xFF8A5B00);
    final fontWeight = header ? FontWeight.w600 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              seq,
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 12, color: color, fontWeight: fontWeight),
            ),
          ),
          Expanded(
            child: Text(
              weight,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: fontWeight,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              price,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: fontWeight,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: fontWeight,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.zeroLabel,
    required this.tareLabel,
    required this.clearLabel,
    required this.addLabel,
    required this.clearAccLabel,
    required this.onDigit,
    required this.onDot,
    required this.onZero,
    required this.onTare,
    required this.onClear,
    required this.onAdd,
    required this.onClearAcc,
  });

  final bool enabled;
  final String zeroLabel;
  final String tareLabel;
  final String clearLabel;
  final String addLabel;
  final String clearAccLabel;
  final Future<void> Function(String) onDigit;
  final Future<void> Function() onDot;
  final Future<void> Function() onZero;
  final Future<void> Function() onTare;
  final Future<void> Function() onClear;
  final Future<void> Function() onAdd;
  final Future<void> Function() onClearAcc;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _key('7', () => onDigit('7')),
          _key('8', () => onDigit('8')),
          _key('9', () => onDigit('9')),
          _key(zeroLabel, onZero, func: true),
          _key('4', () => onDigit('4')),
          _key('5', () => onDigit('5')),
          _key('6', () => onDigit('6')),
          _key(tareLabel, onTare, func: true),
          _key('1', () => onDigit('1')),
          _key('2', () => onDigit('2')),
          _key('3', () => onDigit('3')),
          _key(clearLabel, onClear, func: true),
          _key('0', () => onDigit('0')),
          _key('.', onDot),
          _key(addLabel, onAdd, func: true),
          _key(clearAccLabel, onClearAcc, danger: true),
        ],
      ),
    );
  }

  Widget _key(
    String text,
    Future<void> Function() onTap, {
    bool func = false,
    bool danger = false,
  }) {
    Color bg = const Color(0xFFF5F5F5);
    Color fg = const Color(0xFF1A1A1A);
    if (func) {
      bg = const Color(0xFFE8F0FE);
      fg = const Color(0xFF1A73E8);
    }
    if (danger) {
      bg = const Color(0xFFFDE8E8);
      fg = const Color(0xFFD93025);
    }
    if (!enabled) {
      bg = const Color(0xFFE8E8E8);
      fg = const Color(0xFFAAAAAA);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? () => onTap() : null,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: func || danger ? 16 : (text == '.' ? 24 : 20),
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
