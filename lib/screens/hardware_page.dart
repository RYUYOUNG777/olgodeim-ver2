// lib/screens/hardware_page.dart

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../data/bluetooth_manager.dart';

import 'camera_page.dart'; // ✅ [추가] CameraPage로 이동하기 위해 import




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
  // ✅ [추가] WorkoutSelectionPage로부터 운동 정보를 받기 위한 변수들 추가
  final String muscleGroup;
  final String tool;
  final String workoutName;
  final int setCount;
  final double weight;

  const HardwarePage({
    Key? key,
    required this.muscleGroup,
    required this.tool,
    required this.workoutName,
    required this.setCount,
    required this.weight,
  }) : super(key: key);

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
  int _lostPoseFrameCount = 0; // '발목' 대신 '포즈'를 놓친 프레임으로 변경


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
    // AI가 60% 이상 확신하는 관절만 인정하도록 신뢰도 기준 상향
    const double minLikelihood = 0.6;

    // [2] 얼굴, 어깨, 엉덩이, 무릎, 발목의 인식 정보를 모두 가져옵니다.
    final nose = landmarks[PoseLandmarkType.nose];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];

    // 주요 관절이 "모두" 보여야만 '전신'으로 인정합니다.
    bool faceVisible = (nose?.likelihood ?? 0) > minLikelihood;
    bool shouldersVisible = (leftShoulder?.likelihood ?? 0) > minLikelihood && (rightShoulder?.likelihood ?? 0) > minLikelihood;
    bool hipsVisible = (leftHip?.likelihood ?? 0) > minLikelihood && (rightHip?.likelihood ?? 0) > minLikelihood;
    bool kneesVisible = (leftKnee?.likelihood ?? 0) > minLikelihood && (rightKnee?.likelihood ?? 0) > minLikelihood;
    bool anklesVisible = (leftAnkle?.likelihood ?? 0) > minLikelihood && (rightAnkle?.likelihood ?? 0) > minLikelihood;

    bool fullBodyVisible = faceVisible && shouldersVisible && hipsVisible && kneesVisible && anklesVisible;

    if (fullBodyVisible) {
      _lostPoseFrameCount = 0;
    }

    switch (_status) {
      case HardwareStatus.searching:
        if (!fullBodyVisible) {
          _speak('전신을 찾기 위해 올라갑니다.');
          LinearMotorController.instance.up();
        } else {
          LinearMotorController.instance.stop();
          setState(() => _status = HardwareStatus.centering);
          _speak('전신을 감지했습니다. 구도를 조절합니다.');
        }
        break;

      case HardwareStatus.centering:
        if (!fullBodyVisible) {
          _lostPoseFrameCount++;
          if (_lostPoseFrameCount > 10) {
            setState(() => _status = HardwareStatus.searching);
            _speak('사용자를 놓쳤습니다. 다시 찾습니다.');
          }
          return;
        }

        final imageHeight = _controller!.value.previewSize!.height;
        final topMostPointY = nose!.y;
        final bottomMostPointY = math.max(leftAnkle!.y, rightAnkle!.y);
        final topMargin = imageHeight * 0.10;
        final bottomMargin = imageHeight * 0.85;

        if (topMostPointY < topMargin) {
          _speak('구도를 맞추기 위해 내립니다.');
          LinearMotorController.instance.down();
        } else if (bottomMostPointY > bottomMargin) {
          _speak('구도를 맞추기 위해 올립니다.');
          LinearMotorController.instance.up();
        } else {
          LinearMotorController.instance.stop();
          setState(() {
            _status = HardwareStatus.confirming;
            _countdownValue = 3;
          });
          _startCountdown();
          _speak('구도가 조절되었습니다. 3초 후 고정합니다.', force: true);
        }
        break;

      case HardwareStatus.confirming:
        if (!fullBodyVisible) {
          _lostPoseFrameCount++;
          if (_lostPoseFrameCount > 10) {
            _countdownTimer?.cancel();
            setState(() => _status = HardwareStatus.centering);
            _speak('위치가 변경되어 다시 조절합니다.', force: true);
          }
          return;
        }
        break;

      case HardwareStatus.locked:
      case HardwareStatus.idle:
        break;
    }
  }
////
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
        // ✅ [수정] 조정 완료 후 CameraPage로 자동 이동
        _speak('위치 조정이 완료되었습니다. 운동을 시작합니다.', force: true).then((_) {
          // TTS 안내 후 잠시 대기했다가 페이지 이동
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.pushReplacement( // 뒤로가기 시 이 페이지로 돌아오지 않도록 pushReplacement 사용
                context,
                CupertinoPageRoute(
                  builder: (_) => CameraPage(
                    muscleGroup: widget.muscleGroup,
                    tool: widget.tool,
                    workoutName: widget.workoutName,
                    setCount: widget.setCount,
                    weight: widget.weight,
                  ),
                ),
              );
            }
          });
        });
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
                aspectRatio: 1 / _controller!.value.aspectRatio,
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
                          _controller!.description.sensorOrientation,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // ✅ 카운트다운 상태일 때 애니메이션 위젯을 화면에 표시합니다.
          if (_status == HardwareStatus.confirming) _buildCountdownAnimation(),

          if (_isManualMode && _isBleConnected) _buildManualControls(),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: CupertinoColors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(10)),
              child: Text(
                // ✅ 여기서 카운트다운 숫자를 보여주지 않도록 수정되었습니다.
                _statusMessage,
                style: const TextStyle(color: CupertinoColors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 여기에 붙여넣으세요. (build 함수 바로 다음에 위치)
  /// 카운트다운 애니메이션 위젯을 생성하는 함수
  Widget _buildCountdownAnimation() {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: CupertinoColors.black.withOpacity(0.7),
          shape: BoxShape.circle,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 1.0, end: 0.0),
          duration: const Duration(seconds: 3),
          builder: (context, value, child) {
            return Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  backgroundColor: CupertinoColors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(CupertinoColors.activeGreen),
                ),
                Center(
                  child: Text(
                    _countdownValue.toString(),
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
  final int imageRotation;

  _PosePainter(this.poses, this.absoluteImageSize, this.isFrontCamera, this.imageRotation);

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = CupertinoColors.systemRed
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..strokeWidth = 2.5
      ..color = CupertinoColors.activeGreen;

    if (absoluteImageSize.isEmpty || size.isEmpty) return;

    for (final Pose pose in poses) {
      // ✅ [핵심 수정] 모든 관절 좌표를 화면에 맞게 변환하는 함수
      Offset transform(PoseLandmark landmark) {
        double dx, dy;

        // 센서 방향에 따라 좌표 변환 방식을 다르게 적용합니다.
        if (imageRotation == 90 || imageRotation == 270) {
          // 센서가 가로 방향일 때 (화면은 세로)
          dx = landmark.y * (size.width / absoluteImageSize.height);
          dy = landmark.x * (size.height / absoluteImageSize.width);
        } else {
          // 센서가 세로 방향일 때 (화면도 세로)
          dx = landmark.x * (size.width / absoluteImageSize.width);
          dy = landmark.y * (size.height / absoluteImageSize.height);
        }

        // 전면 카메라인 경우, 거울처럼 보이기 위해 x좌표를 좌우 반전시킵니다.
        if (isFrontCamera) {
          dx = size.width - dx;
        }

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
          old.isFrontCamera != isFrontCamera ||
          old.imageRotation != imageRotation;
}