import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../data/bluetooth_manager.dart';

// 하드웨어의 동작 상태를 관리하기 위한 Enum 정의
enum HardwareStatus {
  searching, // 사용자의 발목을 찾기 위해 올라가는 중 최종최종버전 25-07-06, 22:38기준
  centering, // 전신을 화면 중앙에 맞추는 중
  confirming, // 중앙에 맞춘 후 3초 카운트다운
  locked, // 위치 조정 완료 및 고정
  idle, // 수동 모드 또는 연결 끊김
}

// BLE 컨트롤러
class LinearMotorController {
  LinearMotorController._internal();
  static final instance = LinearMotorController._internal();
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;

  void up() => _bluetoothManager.sendCommand('UP');
  void down() => _bluetoothManager.sendCommand('DOWN');
  void stop() => _bluetoothManager.sendCommand('STOP');
}

// 포즈 스무딩 필터
class PoseSmoother {
  final int windowSize;
  final _landmarkHistory = <PoseLandmarkType, Queue<Offset>>{};

  PoseSmoother({this.windowSize = 5});

  Pose smooth(Pose pose) {
    final smoothedLandmarks = <PoseLandmarkType, PoseLandmark>{};

    for (var entry in pose.landmarks.entries) {
      final type = entry.key;
      final landmark = entry.value;

      _landmarkHistory.putIfAbsent(type, () => Queue<Offset>());
      final history = _landmarkHistory[type]!;
      history.add(Offset(landmark.x, landmark.y));
      if (history.length > windowSize) {
        history.removeFirst();
      }

      double avgX = 0, avgY = 0;
      for (var pos in history) {
        avgX += pos.dx;
        avgY += pos.dy;
      }
      avgX /= history.length;
      avgY /= history.length;

      smoothedLandmarks[type] = PoseLandmark(
        type: landmark.type,
        x: avgX,
        y: avgY,
        z: landmark.z,
        likelihood: landmark.likelihood,
      );
    }
    return Pose(landmarks: smoothedLandmarks);
  }
}

// 메인 화면
class HardwarePage extends StatefulWidget {
  const HardwarePage({Key? key}) : super(key: key);

  @override
  State<HardwarePage> createState() => _HardwarePageState();
}

class _HardwarePageState extends State<HardwarePage> {
  // ── 시스템 & 상태 관리
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;
  final PoseSmoother _poseSmoother = PoseSmoother(windowSize: 5);
  late FlutterTts _flutterTts;
  bool _isBleConnected = false;
  StreamSubscription<bool>? _bleConnectionSubscription;

  // ── 자동 높이 조절을 위한 상태 변수들
  HardwareStatus _status = HardwareStatus.idle;
  Timer? _countdownTimer;
  int _countdownValue = 3;

  // ── 카메라 & ML Kit
  CameraController? _controller;
  PoseDetector? _poseDetector;
  List<Pose> _poses = [];
  bool _isBusy = false;
  bool _isSwitching = false;

  // ── UI
  bool _isManualMode = false;
  Timer? _manualControlTimer;
  String _statusMessage = '하드웨어 연결을 시작합니다...';
  String? _lastTtsMessage;


  @override
  void initState() {
    super.initState();
    _flutterTts = FlutterTts();
    _initCameraAndDetector();
    _initBluetooth();
  }

  @override
  void dispose() {
    _bleConnectionSubscription?.cancel();
    _countdownTimer?.cancel();
    _manualControlTimer?.cancel();
    _controller?.stopImageStream().catchError((e) => debugPrint('카메라 스트림 정지 오류: $e'));
    _controller?.dispose();
    _poseDetector?.close();
    _bluetoothManager.disconnect();
    super.dispose();
  }

  void _initBluetooth() {
    _bleConnectionSubscription = _bluetoothManager.connectionStream.listen((isConnected) {
      if (!mounted) return;
      setState(() {
        _isBleConnected = isConnected;
        if (isConnected && !_isManualMode) {
          _status = HardwareStatus.searching;
          _speak('하드웨어에 연결되었습니다. 높이 조정을 시작합니다.');
        } else {
          _status = HardwareStatus.idle;
          if(isConnected) {
            _speak('수동 모드입니다.');
          } else {
            _speak('하드웨어 연결이 끊어졌습니다. 다시 시도합니다.');
          }
          LinearMotorController.instance.stop();
        }
      });
    });

    if (_bluetoothManager.isConnected) {
      setState(() {
        _isBleConnected = true;
        if (!_isManualMode) {
          _status = HardwareStatus.searching;
          _statusMessage = '하드웨어에 연결되었습니다. 높이 조정을 시작합니다.';
        }
      });
    } else {
      _bluetoothManager.startScanAndConnect();
    }
  }

  Future<void> _speak(String msg, {bool force = false}) async {
    if (msg.isEmpty || (msg == _lastTtsMessage && !force)) return;
    _lastTtsMessage = msg;
    if (mounted) setState(() => _statusMessage = msg);
    await _flutterTts.speak(msg);
  }

  Future<void> _initCameraAndDetector({CameraDescription? desc}) async {
    try {
      final cams = await availableCameras();
      final camDesc = desc ?? cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      _controller = CameraController(
          camDesc,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420
      );
      await _controller!.initialize();
      _poseDetector = PoseDetector(options: PoseDetectorOptions(model: PoseDetectionModel.base, mode: PoseDetectionMode.stream));
      await _controller!.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint('🚨 카메라 초기화 오류: $e');
      _speak('카메라를 시작할 수 없습니다.');
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);
    final currentLens = _controller?.description.lensDirection;
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _poseDetector?.close();
    final cams = await availableCameras();
    final newDesc = cams.firstWhere((c) => c.lensDirection != currentLens, orElse: () => cams.first);
    _poses.clear();
    _lastTtsMessage = null;
    await _initCameraAndDetector(desc: newDesc);
    if (mounted) setState(() => _isSwitching = false);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _poseDetector == null || !mounted || _status == HardwareStatus.locked) return;
    _isBusy = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }
      final detectedPoses = await _poseDetector!.processImage(inputImage);
      final smoothedPoses = detectedPoses.map((pose) => _poseSmoother.smooth(pose)).toList();
      if (mounted) {
        setState(() => _poses = smoothedPoses);
        if (_isBleConnected && !_isManualMode) _evaluatePose();
      }
    } catch (e) {
      debugPrint('🚨 포즈 인식 처리 중 오류: $e');
    } finally {
      if (mounted) _isBusy = false;
    }
  }

  void _evaluatePose() {
    if (_poses.isEmpty) {
      if (_status == HardwareStatus.searching) {
        _speak('사람을 찾기 위해 올라갑니다.');
        LinearMotorController.instance.up();
      } else if (_status != HardwareStatus.locked && _status != HardwareStatus.idle) {
        _speak('사람을 찾고 있습니다...');
      }
      return;
    }

    final pose = _poses.first;
    final landmarks = pose.landmarks;
    const double minLikelihood = 0.4;

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];

    bool shouldersVisible = (leftShoulder?.likelihood ?? 0) > minLikelihood && (rightShoulder?.likelihood ?? 0) > minLikelihood;
    bool anklesVisible = (leftAnkle?.likelihood ?? 0) > minLikelihood && (rightAnkle?.likelihood ?? 0) > minLikelihood;

    switch (_status) {
      case HardwareStatus.searching:
        _speak('전신을 찾기 위해 올라갑니다.');
        LinearMotorController.instance.up();
        if (anklesVisible && shouldersVisible) {
          LinearMotorController.instance.stop();
          setState(() => _status = HardwareStatus.centering);
          _speak('전신을 감지했습니다. 중앙으로 조절합니다.');
        }
        break;

      case HardwareStatus.centering:
        if (!shouldersVisible) {
          _speak('조금 더 올라갑니다.');
          LinearMotorController.instance.up();
          return;
        }
        if (!anklesVisible) {
          _speak('너무 높습니다. 내려갑니다.');
          LinearMotorController.instance.down();
          return;
        }

        final leftHip = landmarks[PoseLandmarkType.leftHip];
        final rightHip = landmarks[PoseLandmarkType.rightHip];
        if (leftHip == null || rightHip == null || leftHip.likelihood < minLikelihood || rightHip.likelihood < minLikelihood) {
          _speak('정확한 자세를 위해 정면을 봐주세요.');
          LinearMotorController.instance.stop();
          return;
        }

        final bodyCenterY = (leftShoulder!.y + rightShoulder!.y + leftAnkle!.y + rightAnkle!.y) / 4;
        final imageHeight = _controller!.value.previewSize!.height;
        final targetTop = imageHeight * 0.45;
        final targetBottom = imageHeight * 0.55;

        if (bodyCenterY < targetTop) {
          _speak('중앙으로 조절합니다.');
          LinearMotorController.instance.down();
        } else if (bodyCenterY > targetBottom) {
          _speak('중앙으로 조절합니다.');
          LinearMotorController.instance.up();
        } else {
          LinearMotorController.instance.stop();
          setState(() {
            _status = HardwareStatus.confirming;
            _countdownValue = 3;
          });
          _startCountdown();
        }
        break;

      case HardwareStatus.confirming:
        final bodyCenterY = (leftShoulder!.y + rightShoulder!.y + leftAnkle!.y + rightAnkle!.y) / 4;
        final imageHeight = _controller!.value.previewSize!.height;
        final targetTop = imageHeight * 0.40;
        final targetBottom = imageHeight * 0.60;
        if(bodyCenterY < targetTop || bodyCenterY > targetBottom || !shouldersVisible || !anklesVisible){
          _countdownTimer?.cancel();
          setState(() => _status = HardwareStatus.centering);
          _speak('위치가 변경되어 다시 조절합니다.', force: true);
        }
        break;

      case HardwareStatus.locked:
      case HardwareStatus.idle:
        break;
    }
  }

  void _startCountdown() {
    _speak('3초 후 위치를 고정합니다... $_countdownValue', force: true);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownValue > 1) {
        setState(() => _countdownValue--);
        _speak('$_countdownValue', force: true);
      } else {
        timer.cancel();
        setState(() => _status = HardwareStatus.locked);
        _speak('위치 조정이 완료되었습니다.', force: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: const EdgeInsets.only(bottom: 4, right: 4),
          onPressed: () {
            setState(() {
              _isManualMode = !_isManualMode;
              LinearMotorController.instance.stop();
              _countdownTimer?.cancel();
              _status = _isManualMode ? HardwareStatus.idle : HardwareStatus.searching;
              _speak(_isManualMode ? '수동 모드로 전환합니다.' : '자동 높이 조절을 시작합니다.');
            });
          },
          child: Icon(_isManualMode ? CupertinoIcons.hand_raised_fill : CupertinoIcons.hand_raised, color: _isManualMode ? CupertinoColors.activeBlue : null),
        ),
        middle: const Text('하드웨어 설정'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_isBleConnected ? CupertinoIcons.bluetooth : CupertinoIcons.xmark_circle, color: _isBleConnected ? CupertinoColors.activeBlue : CupertinoColors.inactiveGray),
            const SizedBox(width: 8),
            CupertinoButton(padding: EdgeInsets.zero, onPressed: _switchCamera, child: const Icon(CupertinoIcons.switch_camera)),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller == null || !_controller!.value.isInitialized || _isSwitching)
            const Center(child: CupertinoActivityIndicator())
          else
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_controller!),
                    if (_poses.isNotEmpty)
                      CustomPaint(
                        painter: _PosePainter(
                          _poses,
                          _controller!.value.previewSize!,
                          _controller!.description.lensDirection == CameraLensDirection.front,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_isManualMode && _isBleConnected) _buildManualControls(),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: CupertinoColors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(10)),
              child: Text(
                _status == HardwareStatus.confirming ? '$_countdownValue' : _statusMessage,
                style: const TextStyle(color: CupertinoColors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualControls() {
    return Positioned(
      right: 20,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: CupertinoColors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _manualBtn(CupertinoIcons.arrow_up, 'UP'),
              const SizedBox(height: 24),
              _manualBtn(CupertinoIcons.stop_fill, 'STOP'),
              const SizedBox(height: 24),
              _manualBtn(CupertinoIcons.arrow_down, 'DOWN'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _manualBtn(IconData icon, String cmd) {
    if (cmd == 'STOP') {
      return GestureDetector(onTap: () => LinearMotorController.instance.stop(), child: Icon(icon, color: CupertinoColors.white, size: 44));
    }
    return GestureDetector(
      onTapDown: (_) => _manualControlTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => cmd == 'UP' ? LinearMotorController.instance.up() : LinearMotorController.instance.down()),
      onTapUp: (_) {
        _manualControlTimer?.cancel();
        LinearMotorController.instance.stop();
      },
      onTapCancel: () {
        _manualControlTimer?.cancel();
        LinearMotorController.instance.stop();
      },
      child: Icon(icon, color: CupertinoColors.white, size: 44),
    );
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (rotation == null) return null;

    final format = defaultTargetPlatform == TargetPlatform.android
        ? InputImageFormat.nv21
        : InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) return null;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final inputImageData = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }
}

/// ✅ 비율 왜곡, 좌우 반전, 위치 쏠림 문제를 모두 해결한 최종 Painter 코드입니다.
class _PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size absoluteImageSize;
  final bool isFrontCamera;

  _PosePainter(this.poses, this.absoluteImageSize, this.isFrontCamera);

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = CupertinoColors.systemRed
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..strokeWidth = 2.5
      ..color = CupertinoColors.activeGreen;

    if (absoluteImageSize.isEmpty) return;

    for (final Pose pose in poses) {
      // 1. 단일 배율 계산 (비율 왜곡 문제 해결)
      final double scaleX = size.width / absoluteImageSize.height;
      final double scaleY = size.height / absoluteImageSize.width;
      final double scale = math.min(scaleX, scaleY);

      // 2. 중앙 정렬을 위한 오프셋 계산 (위치 쏠림 문제 해결)
      final double offsetX = (size.width - absoluteImageSize.height * scale) / 2;
      final double offsetY = (size.height - absoluteImageSize.width * scale) / 2;

      Offset transform(PoseLandmark landmark) {
        final dx = landmark.y * scale + offsetX;
        final dy = landmark.x * scale + offsetY;

        // 3. 좌우 반전 로직 제거 (거울 모드 문제 해결)
        // 전면 카메라는 이미 거울처럼 보이므로, 추가적인 반전이 필요 없습니다.
        return Offset(dx, dy);
      }

      pose.landmarks.forEach((_, landmark) {
        if (landmark.likelihood > 0.5) {
          canvas.drawCircle(transform(landmark), 4, dotPaint);
        }
      });

      void drawLine(PoseLandmarkType type1, PoseLandmarkType type2) {
        final lm1 = pose.landmarks[type1];
        final lm2 = pose.landmarks[type2];
        if (lm1 != null && lm2 != null && lm1.likelihood > 0.5 && lm2.likelihood > 0.5) {
          canvas.drawLine(transform(lm1), transform(lm2), linePaint);
        }
      }

      // 몸통
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      // 팔
      drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);
      // 다리
      drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
    }
  }

  @override
  bool shouldRepaint(_PosePainter old) =>
      old.poses != poses ||
          old.absoluteImageSize != absoluteImageSize ||
          old.isFrontCamera != isFrontCamera;
}