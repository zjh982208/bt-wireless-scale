import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/kt6368_uart.dart';
import '../protocol/scale_protocol.dart';
import 'price_input_engine.dart';


enum AppWorkMode { display, operate }
enum AppLanguage { zh, en }

enum ConnState { idle, scanning, connecting, connected, reconnecting }

enum _ScaleStatus {
    notConnected, // 未连接
    selectDevice, // 请选择设备
    preparingReconnect, // 准备自动重连
    grantBluetooth, // 请授权蓝牙
    grantBluetoothLocation, // 请授权蓝牙和定位
    bluetoothOff, // 蓝牙未打开
    scanning, // 正在扫描
    foundDevices, // 扫描到设备
    scanFailed, // 扫描失败
    connected, // 已连接
    connecting, // 连接中
    connectFailed, // 连接失败
    bluetoothOffWait, // 蓝牙关闭后等待重连
    autoReconnecting, // 自动重连中
    reconnectFailed, // 重连失败
    disconnected, // 已断开
    connectionLost, // 连接断开后重连
    disconnectedManually, // 已手动断开
    scaleNotConnected, // 未连接蓝牙秤
    sendFailed, // 发送失败
}

class CumulativeRecord {
    CumulativeRecord({
        required this.index,
        required this.weight,
        required this.price,
        required this.amount,
    });

    final int index;
    final String weight;
    final String price;
    final String amount;
}

class ScaleController extends ChangeNotifier {
    ScaleController();

    final Kt6368Uart ble = Kt6368Uart();
    final PriceInputEngine priceEngine = PriceInputEngine();
    final List<int> _rxBuf = <int>[];

    AppWorkMode workMode = AppWorkMode.operate;
    ConnState connState = ConnState.idle;
    _ScaleStatus _status = _ScaleStatus.notConnected; // 当前状态，切换语言后按这个重新取文案
    String _statusDetail = ''; // 状态中的设备名、数量或错误信息
    String deviceName = '';
    String deviceId = '';

    String weightText = '0';
    String priceText = '0';
    String totalText = '0';
    String totalAmountText = '0';
    String cumulativeWeightText = '0';
    String timesText = '0';
    String flagText = '-';
    String unitText = 'kg';
    AppLanguage appLanguage = AppLanguage.zh;
    final List<CumulativeRecord> _cumulativeRecords = <CumulativeRecord>[];
    int _lastTimesValue = 0;
    double _lastTotalAmountValue = 0.0;

    bool _autoReconnect = true;
    bool _userDisconnect = false;
    bool _manualSelecting = false;
    Timer? _reconnectTimer;
    Timer? _scanLockTimer;
    int _reconnectAttempt = 0;
    Future<void> _writeQueue = Future<void>.value();
    DateTime _lastModeSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime _scanLockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

    bool get isChinese => appLanguage == AppLanguage.zh;
    List<CumulativeRecord> get cumulativeRecords => UnmodifiableListView(_cumulativeRecords);

    String tr(String zh, String en) {
        return isChinese ? zh : en;
    }

    String get statusText => _statusMessage(); // 按当前语言生成状态文字

    void _setStatus(_ScaleStatus status, [String detail = '']) {
        _status = status; // 只记下状态，不提前翻译
        _statusDetail = detail;
    }

    String _statusMessage() {
        final detail = _statusDetail;
        switch (_status) {
            case _ScaleStatus.notConnected:
                return tr('\u672a\u8fde\u63a5', 'Not connected');
            case _ScaleStatus.selectDevice:
                return tr('\u8bf7\u5728\u5217\u8868\u4e2d\u9009\u62e9\u84dd\u7259\u8bbe\u5907', 'Please select a Bluetooth scale');
            case _ScaleStatus.preparingReconnect:
                return tr('\u51c6\u5907\u81ea\u52a8\u8fde\u63a5 $detail', 'Preparing auto reconnect $detail');
            case _ScaleStatus.grantBluetooth:
                return tr('\u8bf7\u6388\u6743\u84dd\u7259\u6743\u9650', 'Please grant Bluetooth permission');
            case _ScaleStatus.grantBluetoothLocation:
                return tr('\u8bf7\u6388\u6743\u84dd\u7259\u4e0e\u5b9a\u4f4d\u6743\u9650', 'Please grant Bluetooth and location permissions');
            case _ScaleStatus.bluetoothOff:
                return tr(
                    '\u8bf7\u5148\u6253\u5f00\u624b\u673a\u84dd\u7259\uff08\u5f53\u524d\u72b6\u6001: $detail\uff09',
                    'Please turn on Bluetooth (current state: $detail)',
                );
            case _ScaleStatus.scanning:
                return tr('\u6b63\u5728\u626b\u63cf...', 'Scanning...');
            case _ScaleStatus.foundDevices:
                return tr('\u626b\u63cf\u5230 $detail \u4e2a\u8bbe\u5907', 'Found $detail devices');
            case _ScaleStatus.scanFailed:
                return tr('\u626b\u63cf\u5931\u8d25: $detail', 'Scan failed: $detail');
            case _ScaleStatus.connected:
                return tr('\u5df2\u8fde\u63a5 $detail', 'Connected $detail');
            case _ScaleStatus.connecting:
                return tr('\u8fde\u63a5\u4e2d $detail...', 'Connecting $detail...');
            case _ScaleStatus.connectFailed:
                return tr('\u8fde\u63a5\u5931\u8d25: $detail', 'Connect failed: $detail');
            case _ScaleStatus.bluetoothOffWait:
                return tr('\u84dd\u7259\u672a\u5f00\u542f\uff0c\u7b49\u5f85\u91cd\u8fde', 'Bluetooth is off, waiting to reconnect');
            case _ScaleStatus.autoReconnecting:
                return tr('\u81ea\u52a8\u91cd\u8fde $detail...', 'Auto reconnecting $detail...');
            case _ScaleStatus.reconnectFailed:
                return tr('\u91cd\u8fde\u5931\u8d25\uff0c\u7a0d\u540e\u91cd\u8bd5', 'Reconnect failed, retry later');
            case _ScaleStatus.disconnected:
                return tr('\u5df2\u65ad\u5f00', 'Disconnected');
            case _ScaleStatus.connectionLost:
                return tr('\u8fde\u63a5\u65ad\u5f00\uff0c\u81ea\u52a8\u91cd\u8fde\u4e2d...', 'Connection lost, reconnecting...');
            case _ScaleStatus.disconnectedManually:
                return tr('\u5df2\u624b\u52a8\u65ad\u5f00', 'Disconnected manually');
            case _ScaleStatus.scaleNotConnected:
                return tr('\u672a\u8fde\u63a5\u84dd\u7259\u79e4', 'Scale is not connected');
            case _ScaleStatus.sendFailed:
                return tr('\u53d1\u9001\u5931\u8d25: $detail', 'Send failed: $detail');
        }
    }

    bool get canOpenScan {
        if (connState == ConnState.scanning) {
            return false;
        }
        return DateTime.now().isAfter(_scanLockedUntil);
    }

    Future<void> enterManualSelectMode() async {
        _manualSelecting = true; // 手动选择期间暂停自动重连 //
        _autoReconnect = false;
        _reconnectTimer?.cancel();
        if (ble.isConnected) {
            await ble.disconnect(); // 已连接时先断开，避免旧设备持续占用 //
        }
        connState = ConnState.idle;
        _setStatus(_ScaleStatus.selectDevice);
        notifyListeners();
    }

    void exitManualSelectMode() {
        _manualSelecting = false;
        _autoReconnect = true; // 退出手动选择后恢复自动重连能力 //
    }

    void lockScanOpen([Duration duration = const Duration(seconds: 3)]) {
        _scanLockedUntil = DateTime.now().add(duration);
        _scanLockTimer?.cancel();
        _scanLockTimer = Timer(duration, () {
            notifyListeners();
        });
        notifyListeners();
    }

    Future<void> init() async {
        final prefs = await SharedPreferences.getInstance();
        deviceId = prefs.getString('ble_id') ?? '';
        deviceName = prefs.getString('ble_name') ?? '';
        final lang = prefs.getString('app_lang') ?? 'zh';
        appLanguage = lang == 'en' ? AppLanguage.en : AppLanguage.zh;
        final mode = prefs.getString('work_mode') ?? 'operate';
        workMode = mode == 'display' ? AppWorkMode.display : AppWorkMode.operate;

        ble.onDisconnected = _onBleDisconnected;
        ble.onBytes = _onBleBytes;

        if (deviceId.isNotEmpty) {
            _setStatus(_ScaleStatus.preparingReconnect, deviceName);
            notifyListeners();
            unawaited(reconnectSaved());
        }
    }

    Future<void> _saveDevice(String id, String name) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ble_id', id);
        await prefs.setString('ble_name', name);
        deviceId = id;
        deviceName = name;
    }

    Future<void> _saveMode() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'work_mode',
            workMode == AppWorkMode.display ? 'display' : 'operate',
        );
    }

    Future<void> _saveLanguage() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_lang', appLanguage == AppLanguage.zh ? 'zh' : 'en');
    }

    void toggleLanguage() {
        appLanguage = appLanguage == AppLanguage.zh ? AppLanguage.en : AppLanguage.zh;
        unawaited(_saveLanguage());
        notifyListeners();
    }

    Future<bool> ensurePermissions() async {
        if (Platform.isIOS) {
            // iOS 只弹出蓝牙授权。bluetoothScan、bluetoothConnect、定位会直接被拒绝，系统框不会出现。
            final status = await Permission.bluetooth.request();
            return status.isGranted || status.isLimited;
        }
        final req = <Permission>[
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.locationWhenInUse,
        ];
        final statuses = await req.request();
        return statuses.values.every((s) => s.isGranted || s.isLimited);
    }

    Future<BluetoothAdapterState> _readAdapterState() async {
        final now = FlutterBluePlus.adapterStateNow;
        if (now != BluetoothAdapterState.unknown) {
            return now;
        }
        try {
            return await FlutterBluePlus.adapterState
                .where((s) => s != BluetoothAdapterState.unknown)
                .first
                .timeout(const Duration(seconds: 2));
        } catch (_) {
            return FlutterBluePlus.adapterStateNow;
        }
    }

    Future<List<BleDeviceItem>> scanDevices() async {
        final ok = await ensurePermissions();
        if (!ok) {
            _setStatus(Platform.isIOS ? _ScaleStatus.grantBluetooth : _ScaleStatus.grantBluetoothLocation);
            notifyListeners();
            return [];
        }

        final adapterState = await _readAdapterState();
        if (adapterState != BluetoothAdapterState.on) {
            _setStatus(_ScaleStatus.bluetoothOff, adapterState.name);
            notifyListeners();
            return [];
        }

        connState = ConnState.scanning;
        _setStatus(_ScaleStatus.scanning);
        notifyListeners();
        try {
            final list = await Kt6368Uart.scan(timeout: const Duration(seconds: 10));
            if (ble.isConnected && deviceId.isNotEmpty) {
                final hasConnected = list.any((item) => item.device.remoteId.str == deviceId);
                if (!hasConnected) {
                    final connectedDevice = ble.connectedDevice ?? BluetoothDevice.fromId(deviceId);
                    list.insert(
                        0,
                        BleDeviceItem(
                            device: connectedDevice,
                            name: deviceName, // 界面按当前语言加上已连接
                            rssi: 127,
                            markConnected: true,
                        ),
                    );
                }
            }

            connState = ble.isConnected ? ConnState.connected : ConnState.idle;
            _setStatus(_ScaleStatus.foundDevices, '${list.length}');
            notifyListeners();
            return list;
        } catch (e) {
            connState = ConnState.idle;
            _setStatus(_ScaleStatus.scanFailed, '$e');
            notifyListeners();
            return [];
        }
    }

    Future<void> connectDevice(BleDeviceItem item) async {
        if (ble.isConnected && item.id == deviceId) {
            connState = ConnState.connected;
            _setStatus(_ScaleStatus.connected, item.name);
            notifyListeners();
            return;
        }
        _userDisconnect = false;
        _manualSelecting = false;
        _autoReconnect = true;
        _reconnectTimer?.cancel();
        connState = ConnState.connecting;
        _setStatus(_ScaleStatus.connecting, item.name);
        notifyListeners();
        try {
            await ble.connect(item.device, name: item.name);
            await _saveDevice(item.id, item.name);
            _reconnectAttempt = 0;
            connState = ConnState.connected;
            _setStatus(_ScaleStatus.connected, item.name);
            notifyListeners();
            await syncModeToScale();
        } catch (e) {
            connState = ConnState.idle;
            _setStatus(_ScaleStatus.connectFailed, '$e');
            notifyListeners();
        }
    }

    Future<void> reconnectSaved() async {
        if (deviceId.isEmpty || _userDisconnect || _manualSelecting) {
            return;
        }
        final ok = await ensurePermissions();
        if (!ok) {
            return;
        }

        final adapterState = await _readAdapterState();
        if (adapterState != BluetoothAdapterState.on) {
            _setStatus(_ScaleStatus.bluetoothOffWait);
            connState = ConnState.reconnecting;
            notifyListeners();
            _scheduleReconnect();
            return;
        }

        connState = ConnState.reconnecting;
        _setStatus(_ScaleStatus.autoReconnecting, deviceName);
        notifyListeners();
        try {
            await ble.connectById(deviceId, name: deviceName);
            _reconnectAttempt = 0;
            connState = ConnState.connected;
            _setStatus(_ScaleStatus.connected, deviceName);
            notifyListeners();
            await syncModeToScale();
        } catch (_) {
            _setStatus(_ScaleStatus.reconnectFailed);
            notifyListeners();
            _scheduleReconnect();
        }
    }

    void _scheduleReconnect() {
        if (!_autoReconnect || _userDisconnect || deviceId.isEmpty || _manualSelecting) {
            return;
        }
        _reconnectTimer?.cancel();
        const delays = [1, 2, 5, 8, 15, 30];
        final sec = delays[_reconnectAttempt.clamp(0, delays.length - 1)];
        _reconnectAttempt += 1;
        _reconnectTimer = Timer(Duration(seconds: sec), () {
            unawaited(reconnectSaved());
        });
    }

    void _onBleDisconnected() {
        if (_userDisconnect || _manualSelecting) {
            connState = ConnState.idle;
            _setStatus(_ScaleStatus.disconnected);
            notifyListeners();
            return;
        }
        connState = ConnState.reconnecting;
        _setStatus(_ScaleStatus.connectionLost);
        notifyListeners();
        _scheduleReconnect();
    }

    void _onBleBytes(List<int> bytes) {
        _rxBuf.addAll(bytes);
        final frames = ScaleProtocol.extractFrames(_rxBuf);
        if (frames.isEmpty) {
            return;
        }
        final frame = frames.last;
        weightText = _normalizeNumberText(frame.displayWeight, maxDigits: 5, maxFracDigits: 3);
        if (workMode == AppWorkMode.display || !priceEngine.isEditing) {
            priceText = _normalizeNumberText(frame.priceText, maxDigits: 5, maxFracDigits: 2);
        } else {
            priceText = priceEngine.displayText;
        }
        totalText = ScaleProtocol.displayAmount7(frame.totalText);
        totalAmountText = ScaleProtocol.displayAmount7(frame.totalAmountText);
        timesText = frame.timesText.trim().replaceFirst(RegExp(r'^0+(?=.)'), '');
        if (timesText.isEmpty) {
            timesText = '0';
        }
        flagText = frame.flag;
        unitText = frame.unit.trim().isEmpty ? 'kg' : frame.unit.trim();
        _updateCumulativeRecords(frame);
        notifyListeners();
    }

    void _updateCumulativeRecords(ScaleFrameData frame) {
        final timesValue = int.tryParse(timesText) ?? 0;
        final totalAmountValue = double.tryParse(totalAmountText) ?? 0.0;
        if (timesValue <= 0 || totalAmountValue <= 0.0) {
            _cumulativeRecords.clear();
            cumulativeWeightText = '0';
            _lastTimesValue = timesValue;
            _lastTotalAmountValue = totalAmountValue;
            return;
        }

        if (timesValue < _lastTimesValue || totalAmountValue < _lastTotalAmountValue) {
            _cumulativeRecords.clear();
            cumulativeWeightText = '0';
            _lastTimesValue = 0;
            _lastTotalAmountValue = 0.0;
        }

        if (timesValue > _lastTimesValue) {
            var addCount = timesValue - _lastTimesValue;
            if (addCount <= 0) {
                addCount = 1;
            }
            final entryWeight = _normalizeNumberText(frame.displayWeight, maxDigits: 5, maxFracDigits: 3);
            final entryPrice = _normalizeNumberText(frame.priceText, maxDigits: 5, maxFracDigits: 2);
            // 本笔金额用秤上报的总价，不再用累计差额自己计算。
            final entryAmount = ScaleProtocol.displayAmount7(frame.totalText);
            for (var i = 0; i < addCount; i++) {
                _cumulativeRecords.add(
                    CumulativeRecord(
                        index: _cumulativeRecords.length + 1,
                        weight: entryWeight,
                        price: entryPrice,
                        amount: entryAmount,
                    ),
                );
            }
        }

        _lastTimesValue = timesValue;
        _lastTotalAmountValue = totalAmountValue;
        double totalWeight = 0.0;
        for (final item in _cumulativeRecords) {
            totalWeight += double.tryParse(item.weight) ?? 0.0;
        }
        cumulativeWeightText = _normalizeNumberText(totalWeight.toStringAsFixed(3), maxDigits: 6, maxFracDigits: 3);
    }

    String _normalizeNumberText(
        String raw, {
        required int maxDigits,
        required int maxFracDigits,
    }) {
        final src = raw.trim();
        if (src.isEmpty) {
            return '0';
        }
        final negative = src.startsWith('-');
        final cleaned = src.replaceAll(RegExp(r'[^0-9.]'), '');
        if (cleaned.isEmpty) {
            return negative ? '-0' : '0';
        }
        final dot = cleaned.indexOf('.');
        String intPart = dot >= 0 ? cleaned.substring(0, dot) : cleaned;
        String fracPart = dot >= 0 ? cleaned.substring(dot + 1) : '';
        intPart = intPart.replaceFirst(RegExp(r'^0+(?=.)'), '');
        if (intPart.isEmpty) {
            intPart = '0';
        }
        if (intPart.length > maxDigits) {
            intPart = intPart.substring(intPart.length - maxDigits);
            fracPart = '';
        }
        var remain = maxDigits - intPart.length;
        if (remain < 0) {
            remain = 0;
        }
        var allowFrac = remain;
        if (allowFrac > maxFracDigits) {
            allowFrac = maxFracDigits;
        }
        if (allowFrac <= 0 || fracPart.isEmpty) {
            return negative ? '-$intPart' : intPart;
        }
        fracPart = fracPart.substring(0, allowFrac);
        return negative ? '-$intPart.$fracPart' : '$intPart.$fracPart';
    }

    Future<void> syncModeToScale() async {
        if (!ble.isConnected) {
            return;
        }
        if (workMode == AppWorkMode.operate) {
            await _writeSafe(ScaleProtocol.buildModeDisplayCmd());
        } else {
            await _writeSafe(ScaleProtocol.buildModeOperateCmd());
        }
        _lastModeSyncAt = DateTime.now();
    }

    Future<void> _ensurePhoneCanControl() async {
        if (!ble.isConnected || workMode != AppWorkMode.operate) {
            return;
        }
        final now = DateTime.now();
        if (now.difference(_lastModeSyncAt) >= const Duration(seconds: 1)) {
            await _writeSafe(ScaleProtocol.buildModeDisplayCmd());
            _lastModeSyncAt = now;
        }
    }

    void toggleWorkMode() {
        workMode = workMode == AppWorkMode.operate ? AppWorkMode.display : AppWorkMode.operate;
        unawaited(_saveMode());
        notifyListeners();
        unawaited(syncModeToScale());
    }

    Future<void> disconnectManual() async {
        _userDisconnect = true;
        _autoReconnect = false;
        _reconnectTimer?.cancel();
        await ble.disconnect();
        connState = ConnState.idle;
        _setStatus(_ScaleStatus.disconnectedManually);
        notifyListeners();
    }

    Future<void> _writeSafe(List<int> data) async {
        if (!ble.isConnected) {
            _setStatus(_ScaleStatus.scaleNotConnected);
            notifyListeners();
            return;
        }
        _writeQueue = _writeQueue.then((_) async {
            try {
                await ble.write(data);
            } catch (e) {
                _setStatus(_ScaleStatus.sendFailed, '$e');
                notifyListeners();
            }
        });
        await _writeQueue;
    }

    Future<void> sendPriceNow() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        await _ensurePhoneCanControl();
        priceText = priceEngine.displayText;
        notifyListeners();
        await _writeSafe(ScaleProtocol.buildPriceFrame(priceEngine.priceValue));
    }

    Future<void> onDigit(String d) async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        if (priceEngine.inputDigit(d)) {
            await sendPriceNow();
        }
    }

    Future<void> onDot() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        priceEngine.inputDot();
        await sendPriceNow();
    }

    Future<void> onClearPrice() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        await _ensurePhoneCanControl();
        priceEngine.clear();
        priceText = '0';
        notifyListeners();
        await _writeSafe(ScaleProtocol.buildPriceFrame(0));
    }

    Future<void> onZero() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        await _ensurePhoneCanControl();
        await _writeSafe(ScaleProtocol.buildZeroCmd());
    }

    Future<void> onTare() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        await _ensurePhoneCanControl();
        await _writeSafe(ScaleProtocol.buildTareCmd());
    }

    Future<void> onAdd() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        await _ensurePhoneCanControl();
        await _writeSafe(ScaleProtocol.buildAddCmd());
    }

    Future<void> onClearAcc() async {
        if (workMode != AppWorkMode.operate) {
            return;
        }
        await _ensurePhoneCanControl();
        _cumulativeRecords.clear();
        cumulativeWeightText = '0';
        _lastTimesValue = 0;
        _lastTotalAmountValue = 0.0;
        timesText = '0';
        totalAmountText = '0';
        notifyListeners();
        await _writeSafe(ScaleProtocol.buildClearAccCmd());
    }

    @override
    void dispose() {
        _reconnectTimer?.cancel();
        _scanLockTimer?.cancel();
        ble.disconnect();
        super.dispose();
    }
}
