import 'package:flutter/material.dart';

import '../app/scale_controller.dart';
import '../ble/kt6368_uart.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.controller});

  final ScaleController controller;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  List<BleDeviceItem> _devices = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController); // 语言或状态变化时刷新本页
    _startScan();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (mounted) {
      setState(() {}); // 切换语言后重绘设备名和状态
    }
  }

  String _deviceTitle(BleDeviceItem item) {
    if (!item.markConnected) {
      return item.name;
    }
    final isChinese = widget.controller.isChinese;
    if (item.name.isEmpty) {
      return isChinese ? '\u5df2\u8fde\u63a5\u8bbe\u5907' : 'Connected device';
    }
    return isChinese ? '${item.name} (\u5df2\u8fde\u63a5)' : '${item.name} (connected)';
  }

  Future<void> _startScan() async {
    setState(() {
      _loading = true;
    });
    final list = await widget.controller.scanDevices();
    if (!mounted) {
      return;
    }
    setState(() {
      _devices = list;
      _loading = false;
    });
  }

  Future<void> _connect(BleDeviceItem item) async {
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = widget.controller.isChinese;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChinese ? '\u626b\u63cf\u84dd\u7259\u79e4' : 'Scan Bluetooth Scale'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _startScan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.controller.statusText.isEmpty
                              ? (isChinese ? '\u672a\u53d1\u73b0\u8bbe\u5907' : 'No device found')
                              : widget.controller.statusText, // 状态随当前语言变化
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _startScan,
                          child: Text(isChinese ? '\u91cd\u65b0\u626b\u63cf' : 'Scan again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final d = _devices[index];
                    return ListTile(
                      leading: const Icon(Icons.bluetooth, color: Color(0xFF1A73E8)),
                      title: Text(_deviceTitle(d)),
                      subtitle: Text('${d.id}  RSSI ${d.rssi}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _connect(d),
                    );
                  },
                ),
    );
  }
}
