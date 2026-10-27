import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// KT6368A BLE UART UUIDs (same as burner app)
const ktServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const ktNotifyUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
const ktWriteUuid = '0000fff3-0000-1000-8000-00805f9b34fb';
const writeGap = Duration(milliseconds: 4);

class BleDeviceItem {
  BleDeviceItem({required this.device, required this.name, required this.rssi});

  final BluetoothDevice device;
  final String name;
  final int rssi;

  String get id => device.remoteId.str;
}

/// KT6368A transparent UART wrapper.
class Kt6368Uart {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<int>>? _notifySubCompat;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  final List<int> _rx = <int>[];
  var _chunkSize = 20;
  var isConnected = false;
  String portName = '';
  String deviceId = '';
  String deviceName = '';
  BluetoothDevice? get connectedDevice => _device;

  void Function(String msg)? onLog;
  void Function()? onDisconnected;
  void Function(Uint8List bytes)? onBytes;

  void _handleNotifyValue(List<int> value) {
    if (value.isEmpty) {
      return;
    }
    _rx.addAll(value);
    if (_rx.length > 65536) {
      _rx.removeRange(0, _rx.length - 32768);
    }
    onBytes?.call(Uint8List.fromList(value));
  }

  static Future<List<BleDeviceItem>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await FlutterBluePlus.stopScan();
    final found = <String, BleDeviceItem>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.trim().isNotEmpty
            ? r.advertisementData.advName.trim()
            : (r.device.platformName.trim().isNotEmpty
                ? r.device.platformName.trim()
                : '(no-name)');
        found[r.device.remoteId.str] = BleDeviceItem(
          device: r.device,
          name: name,
          rssi: r.rssi,
        );
      }
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    while (FlutterBluePlus.isScanningNow) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await FlutterBluePlus.stopScan();
    await sub.cancel();
    final devices = found.values.toList()
      ..sort((a, b) {
        final aScore = _preferScore(a.name);
        final bScore = _preferScore(b.name);
        if (aScore != bScore) {
          return bScore.compareTo(aScore);
        }
        return b.rssi.compareTo(a.rssi);
      });
    return devices;
  }

  static int _preferScore(String name) {
    final upper = name.toUpperCase();
    if (upper.contains('KT6368')) {
      return 100;
    }
    if (upper.contains('SD') || upper.contains('SCALE')) {
      return 50;
    }
    return 0;
  }

  Future<void> connect(BluetoothDevice device, {String name = ''}) async {
    await disconnect();
    _device = device;
    deviceId = device.remoteId.str;
    deviceName = name.isNotEmpty ? name : device.platformName;
    portName = 'BLE:$deviceName';
    await device.connect(
      timeout: const Duration(seconds: 20),
      autoConnect: false,
      mtu: 247,
    );
    isConnected = true;
    _stateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        isConnected = false;
        onDisconnected?.call();
      }
    });
    try {
      await device.requestMtu(247);
    } catch (_) {}
    final mtu = device.mtuNow;
    _chunkSize = (mtu - 3).clamp(20, 180);
    await _selectChars(device);
    if (_notifyChar == null || _writeChar == null) {
      throw StateError('ble uart uuid not found, expect FFF0/FFF1/FFF3');
    }
    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.lastValueStream.listen(_handleNotifyValue);
    _notifySubCompat = _notifyChar!.onValueReceived.listen(_handleNotifyValue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> connectById(String id, {String name = ''}) async {
    final device = BluetoothDevice.fromId(id);
    await connect(device, name: name);
  }

  Future<void> _selectChars(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothCharacteristic? notifyChar;
    BluetoothCharacteristic? writeChar;
    BluetoothCharacteristic? fff1;
    BluetoothCharacteristic? fff3;
    for (final svc in services) {
      for (final ch in svc.characteristics) {
        final uuid = ch.uuid.toString().toLowerCase();
        if (uuid == ktNotifyUuid || uuid.contains('fff1')) {
          fff1 = ch;
        }
        if (uuid == ktWriteUuid || uuid.contains('fff3')) {
          fff3 = ch;
        }
      }
    }
    notifyChar = fff1;
    writeChar = fff3 ?? fff1;
    if (notifyChar == null || writeChar == null) {
      for (final svc in services) {
        for (final ch in svc.characteristics) {
          if (notifyChar == null && ch.properties.notify) {
            notifyChar = ch;
          }
          final canWrite =
              ch.properties.writeWithoutResponse || ch.properties.write;
          if (writeChar == null && canWrite && ch != notifyChar) {
            writeChar = ch;
          }
        }
      }
      writeChar ??= notifyChar;
    }
    _notifyChar = notifyChar;
    _writeChar = writeChar;
  }

  Future<void> write(List<int> data) async {
    if (!isConnected || _writeChar == null) {
      throw StateError('ble is not connected');
    }
    var offset = 0;
    while (offset < data.length) {
      final end =
          (offset + _chunkSize) > data.length ? data.length : offset + _chunkSize;
      final part = data.sublist(offset, end);
      try {
        await _writeChar!.write(part, withoutResponse: true);
      } catch (_) {
        await _writeChar!.write(part, withoutResponse: false);
      }
      offset = end;
      if (offset < data.length) {
        await Future<void>.delayed(writeGap);
      }
    }
  }

  void resetInput() {
    _rx.clear();
  }

  Future<void> disconnect() async {
    isConnected = false;
    await _notifySub?.cancel();
    await _notifySubCompat?.cancel();
    await _stateSub?.cancel();
    _notifySub = null;
    _notifySubCompat = null;
    _stateSub = null;
    try {
      await _notifyChar?.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _rx.clear();
  }
}
