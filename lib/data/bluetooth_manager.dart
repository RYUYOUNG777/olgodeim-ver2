// lib/data/bluetooth_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothManager {
  BluetoothManager._internal();
  static final BluetoothManager instance = BluetoothManager._internal();

  final Guid serviceUUID = Guid("12345678-1234-1234-1234-1234567890ab");
  final Guid characteristicUUID = Guid("abcd1234-abcd-1234-abcd-1234567890ab");

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  final StreamController<bool> _connectionStreamController = StreamController.broadcast();
  Stream<bool> get connectionStream => _connectionStreamController.stream;

  bool get isConnected => _device != null && _characteristic != null;

  /// ❗❗❗ [수정됨] 권한을 확인하고 요청하는 새로운 함수 ❗❗❗
  Future<bool> _requestPermissions() async {
    // 안드로이드 12 이상에서는 블루투스 관련 권한을 직접 요청해야 합니다.
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.location]!.isGranted &&
        statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted) {
      return true;
    } else {
      debugPrint("🚨 필수 권한이 거부되었습니다.");
      return false;
    }
  }

  /// ❗❗❗ [수정됨] 스캔 시작 전에 권한 확인 로직 추가 ❗❗❗
  Future<void> startScanAndConnect() async {
    if (FlutterBluePlus.isScanningNow || isConnected) {
      debugPrint("이미 스캔 중이거나 연결되었습니다.");
      return;
    }

    // 1. 권한 확인 및 요청
    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      _connectionStreamController.add(false);
      return; // 권한이 없으면 스캔을 시작하지 않음
    }

    // 2. 블루투스 어댑터 상태 확인
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      debugPrint("블루투스가 꺼져 있습니다.");
      _connectionStreamController.add(false);
      return;
    }

    // 3. 스캔 시작
    debugPrint("블루투스 스캔을 시작합니다...");
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        debugPrint("--- 주변 기기 목록 ---");
        for (ScanResult r in results) {
          String deviceName = r.device.platformName.isEmpty ? '(unknown)' : r.device.platformName;
          debugPrint("찾음: $deviceName, ID: ${r.device.remoteId}");
        }
        debugPrint("--------------------");
      }

      for (ScanResult r in results) {
        if (r.device.platformName == 'ESP32_Actuator') {
          debugPrint("🎯 목표 기기('ESP32_Actuator') 발견! 연결을 시도합니다.");
          _device = r.device;
          FlutterBluePlus.stopScan();
          _scanSubscription?.cancel();
          _connectToDevice();
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    Future.delayed(const Duration(seconds: 16), () {
      if (!isConnected && _device == null) {
        FlutterBluePlus.stopScan();
        debugPrint("⏰ 스캔 시간이 초과되었습니다. 기기를 찾지 못했습니다.");
        _connectionStreamController.add(false);
      }
    });
  }

  /// 기기 연결
  Future<void> _connectToDevice() async {
    if (_device == null) return;

    await _connectionStateSubscription?.cancel();

    _connectionStateSubscription = _device!.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        debugPrint("✅ ${_device!.remoteId.str}에 연결되었습니다.");
        await _discoverServices();
      } else if (state == BluetoothConnectionState.disconnected) {
        debugPrint("❌ ${_device!.remoteId.str}의 연결이 끊어졌습니다.");
        _characteristic = null;
        _connectionStreamController.add(false);
      }
    });

    try {
      await _device!.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      debugPrint("🚨 연결 실패: $e");
      _connectionStreamController.add(false);
    }
  }

  /// 서비스 및 특성 탐색
  Future<void> _discoverServices() async {
    if (_device == null) return;

    try {
      List<BluetoothService> services = await _device!.discoverServices();
      for (var service in services) {
        if (service.uuid == serviceUUID) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == characteristicUUID) {
              _characteristic = characteristic;
              debugPrint("🎯 목표 특성을 찾았습니다: ${characteristic.uuid}");
              _connectionStreamController.add(true);
              return;
            }
          }
        }
      }
      debugPrint("🚨 목표 특성을 찾지 못했습니다.");
      _connectionStreamController.add(false);
    } catch (e) {
      debugPrint("🚨 서비스 탐색 중 오류 발생: $e");
      _connectionStreamController.add(false);
    }
  }

  /// 데이터(명령) 전송
  Future<void> sendCommand(String command) async {
    if (_characteristic == null) {
      debugPrint("명령 전송 실패: 특성을 찾지 못했습니다.");
      return;
    }

    try {
      await _characteristic!.write(utf8.encode(command), withoutResponse: false);
      debugPrint("명령 전송 완료: $command");
    } catch (e) {
      debugPrint("명령 전송 중 오류 발생: $e");
    }
  }

  /// 연결 해제
  void disconnect() {
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _device?.disconnect();
    _characteristic = null;
    _device = null;
    _connectionStreamController.add(false);
    debugPrint("연결을 해제합니다.");
  }
}
