// lib/screens/manual_control_page.dart

import 'package:final_graduation_work/data/bluetooth_manager.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';

// 기존 HardwarePage에서 사용하던 컨트롤러 로직을 그대로 가져와 재사용합니다.
class LinearMotorController {
  LinearMotorController._internal();
  static final instance = LinearMotorController._internal();
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;

  void up() => _bluetoothManager.sendCommand('UP');
  void down() => _bluetoothManager.sendCommand('DOWN');
  void stop() => _bluetoothManager.sendCommand('STOP');
}

class ManualControlPage extends StatefulWidget {
  const ManualControlPage({Key? key}) : super(key: key);

  @override
  _ManualControlPageState createState() => _ManualControlPageState();
}

class _ManualControlPageState extends State<ManualControlPage> {
  Timer? _manualControlTimer;

  @override
  void dispose() {
    // 페이지가 화면에서 사라질 때, 실행 중일 수 있는 타이머를 확실히 취소하고 모터를 정지시킵니다.
    _manualControlTimer?.cancel();
    LinearMotorController.instance.stop();
    super.dispose();
  }

  // 수동 조작 버튼 위젯입니다.
  // 버튼을 누르고 있는 동안 계속 동작하도록 GestureDetector를 사용합니다.
  Widget _manualBtn(IconData icon, String cmd, {bool isStopButton = false}) {
    // '정지' 버튼일 경우, 한 번만 탭하면 바로 정지 명령을 보냅니다.
    if (isStopButton) {
      return GestureDetector(
        onTap: () => LinearMotorController.instance.stop(),
        child: Icon(icon, color: CupertinoColors.white, size: 60),
      );
    }

    // '위', '아래' 버튼일 경우
    return GestureDetector(
      onTapDown: (_) {
        // 버튼을 누르기 시작하면 0.1초마다 주기적으로 명령을 보냅니다.
        _manualControlTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (cmd == 'UP') {
            LinearMotorController.instance.up();
          } else {
            LinearMotorController.instance.down();
          }
        });
      },
      onTapUp: (_) {
        // 버튼에서 손을 떼면 타이머를 취소하고 정지 명령을 보냅니다.
        _manualControlTimer?.cancel();
        LinearMotorController.instance.stop();
      },
      onTapCancel: () {
        // 드래그 등 탭이 비정상적으로 취소될 경우에도 정지시킵니다.
        _manualControlTimer?.cancel();
        LinearMotorController.instance.stop();
      },
      child: Icon(icon, color: CupertinoColors.white, size: 80),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.darkBackgroundGray,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('수동 높이 조절'),
        previousPageTitle: '홈', // 뒤로가기 버튼 옆에 표시될 텍스트
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _manualBtn(CupertinoIcons.arrow_up_circle_fill, 'UP'),
              _manualBtn(CupertinoIcons.stop_circle_fill, 'STOP', isStopButton: true),
              _manualBtn(CupertinoIcons.arrow_down_circle_fill, 'DOWN'),
            ],
          ),
        ),
      ),
    );
  }
}