import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../data/bluetooth_manager.dart';

/// ---------------------------------------------------------------------------
/// BLE를 통한 리니어 모터 제어
/// ---------------------------------------------------------------------------
class LinearMotorController {
  LinearMotorController._internal();
  static final instance = LinearMotorController._internal();
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;

  void up()   => _bluetoothManager.sendCommand('UP');
  void down() => _bluetoothManager.sendCommand('DOWN');
  void stop() => _bluetoothManager.sendCommand('STOP');
}

/// ---------------------------------------------------------------------------
/// 메인 화면
/// ---------------------------------------------------------------------------
class HardwarePage extends StatefulWidget {
  const HardwarePage({Key? key}) : super(key: key);

  @override
  State<HardwarePage> createState() => _HardwarePageState();
}

class _HardwarePageState extends State<HardwarePage> {
  // ── Bluetooth
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;
  bool _isBleConnected = false;
  StreamSubscription<bool>? _bleConnectionSubscription;

  // ── Camera & ML Kit
  CameraController? _controller;
  FaceDetector? _faceDetector;
  late FlutterTts _flutterTts;

  List<Face> _faces = [];
  bool _isBusy = false;
  bool _isSwitching = false;

  // ── 수동 / 자동 모드
  bool _isManualMode = false;
  Timer? _manualControlTimer;

  // ── 얼굴 평가 상태
  bool _heightAligned = false;
  bool _distanceOk    = false;
  Timer? _maintainTimer;

  // ── UI
  String _statusMessage   = '하드웨어 연결을 시작합니다...';
  String? _lastTtsMessage;
  double _currentFaceRatio = 0.0;

  // --------------------------------------------------------------------------
  // 생명주기
  // --------------------------------------------------------------------------
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
    _maintainTimer?.cancel();
    _manualControlTimer?.cancel();

    _controller?.stopImageStream().catchError(
            (e) => debugPrint('카메라 스트림 정지 오류: $e'));
    _controller?.dispose();
    _faceDetector?.close();

    _bluetoothManager.disconnect();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Bluetooth 초기화
  // --------------------------------------------------------------------------
  void _initBluetooth() {
    setState(() {
      _isBleConnected = _bluetoothManager.isConnected;
      _statusMessage  = _isBleConnected
          ? '하드웨어에 연결되었습니다.'
          : '하드웨어를 찾는 중입니다...';
    });

    _bleConnectionSubscription =
        _bluetoothManager.connectionStream.listen((isConnected) {
          if (!mounted) return;
          setState(() {
            _isBleConnected = isConnected;
            if (isConnected) {
              _speak('하드웨어에 연결되었습니다.');
            } else {
              _speak('하드웨어 연결이 끊어졌습니다. 다시 시도합니다.');
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted && !_isBleConnected) {
                  _bluetoothManager.startScanAndConnect();
                }
              });
            }
          });
        });

    if (!_isBleConnected) _bluetoothManager.startScanAndConnect();
  }

  // --------------------------------------------------------------------------
  // TTS 헬퍼
  // --------------------------------------------------------------------------
  Future<void> _speak(String msg) async {
    if (msg.isEmpty || msg == _lastTtsMessage) return;
    _lastTtsMessage = msg;
    if (mounted) setState(() => _statusMessage = msg);
    await _flutterTts.speak(msg);
  }

  // --------------------------------------------------------------------------
  // 카메라 & 얼굴검출기 초기화
  // --------------------------------------------------------------------------
  Future<void> _initCameraAndDetector({CameraDescription? desc}) async {
    try {
      final cams = await availableCameras();
      final camDesc = desc ??
          cams.firstWhere(
                  (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => cams.first);

      _controller = CameraController(
        camDesc,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: true,
          enableContours: true,
        ),
      );

      await _controller!.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint('🚨 카메라 초기화 오류: $e');
      _speak('카메라를 시작할 수 없습니다.');
    }
    if (mounted) setState(() {});
  }

  // --------------------------------------------------------------------------
  // 전·후면 전환
  // --------------------------------------------------------------------------
  Future<void> _switchCamera() async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);

    final currentLens = _controller?.description.lensDirection;

    await _controller?.stopImageStream();
    await _controller?.dispose();
    _faceDetector?.close();

    final cams = await availableCameras();
    final newDesc = cams.firstWhere(
            (c) => c.lensDirection != currentLens,
        orElse: () => cams.first);

    _faces.clear();
    _heightAligned = false;
    _distanceOk    = false;
    _maintainTimer?.cancel();
    _lastTtsMessage = null;

    await _initCameraAndDetector(desc: newDesc);

    if (mounted) setState(() => _isSwitching = false);
  }

  // --------------------------------------------------------------------------
  // 이미지 프레임 처리 및 얼굴 검출
  // --------------------------------------------------------------------------
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _faceDetector == null || !mounted) return;
    _isBusy = true;

    try {
      // ── ① Plane 합치기
      final WriteBuffer buffer = WriteBuffer();
      for (final Plane p in image.planes) {
        buffer.putUint8List(p.bytes);
      }
      final Uint8List bytes = buffer.done().buffer.asUint8List();

      // ── ② 메타데이터 구성
      final ui.Size size = ui.Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final rotation = InputImageRotationValue.fromRawValue(
          _controller!.description.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final format = defaultTargetPlatform == TargetPlatform.android
          ? InputImageFormat.nv21
          : InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      // ── ③ InputImage 생성 후 얼굴검출
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);

      // ── ④ 상태 업데이트 & 평가
      if (mounted) {
        setState(() => _faces = faces);
        if (_isBleConnected) _evaluateFaces();
      }
    } catch (e) {
      debugPrint('🚨 얼굴 인식 처리 중 오류: $e');
    } finally {
      if (mounted) _isBusy = false;
    }
  }

  // --------------------------------------------------------------------------
  // ★ 수정됨: 얼굴 위치·거리 평가 → 모터 제어 (안정적인 로직으로 교체)
  // --------------------------------------------------------------------------
  void _evaluateFaces() {
    if (_isManualMode || !_isBleConnected) return;

    final screenSize = MediaQuery.of(context).size;

    if (_faces.isEmpty) {
      _heightAligned = false;
      _distanceOk = false;
      _maintainTimer?.cancel();
      _speak('얼굴이 검출되지 않았습니다.');
      LinearMotorController.instance.stop(); // 얼굴 없으면 정지
      if(mounted) setState(() => _currentFaceRatio = 0.0);
      return;
    }

    final face = _faces.first;
    final faceCenterY = face.boundingBox.center.dy;
    final faceHeightRatio = face.boundingBox.height / screenSize.height;

    if(mounted) setState(() => _currentFaceRatio = faceHeightRatio);

    const double TOO_CLOSE_THRESHOLD = 0.18;
    const double TOO_FAR_THRESHOLD = 0.12;

    // ── ① 높이 맞춤
    if (!_heightAligned) {
      final double targetTop = screenSize.height * 0.4;
      final double targetBottom = screenSize.height * 0.6;

      if (faceCenterY < targetTop) {
        LinearMotorController.instance.down();
        _speak('높이를 조정합니다.');
      } else if (faceCenterY > targetBottom) {
        LinearMotorController.instance.up();
        _speak('높이를 조정합니다.');
      } else {
        _heightAligned = true;
        LinearMotorController.instance.stop();
        _speak('적정 높이에 도달했습니다.');
      }
      return;
    }

    // ── ② 높이 범위 유지 여부 확인
    final double currentFaceYRatio = faceCenterY / screenSize.height;
    if (currentFaceYRatio < 0.35 || currentFaceYRatio > 0.65) {
      setState(() {
        _heightAligned = false;
      });
      return;
    }

    // ── ③ 거리 평가 (높이가 맞춰진 후에만 실행)
    if (_heightAligned) {
      if (faceHeightRatio > TOO_CLOSE_THRESHOLD) {
        _distanceOk = false;
        _maintainTimer?.cancel();
        _speak('거리가 너무 가깝습니다. 뒤로 가주세요.');
      } else if (faceHeightRatio < TOO_FAR_THRESHOLD) {
        _distanceOk = false;
        _maintainTimer?.cancel();
        _speak('거리가 너무 멉니다. 앞으로 오세요.');
      } else {
        // 적정 거리에 처음 도달했을 때
        if (!_distanceOk) {
          _distanceOk = true;
          _maintainTimer?.cancel();
          _speak('적정 거리에 도달했습니다. 3초간 유지해주세요.');
          _maintainTimer = Timer(const Duration(seconds: 3), () {
            _speak('위치 조정이 완료되었습니다.');
          });
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // UI (Cupertino)
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: const EdgeInsets.only(bottom: 4, right: 4),
          onPressed: () {
            setState(() {
              _isManualMode = !_isManualMode;
              LinearMotorController.instance.stop();
              _speak(_isManualMode ? '수동 모드로 전환합니다.' : '자동 모드로 전환합니다.');
            });
          },
          child: Icon(
            _isManualMode
                ? CupertinoIcons.hand_raised_fill
                : CupertinoIcons.hand_raised,
            color: _isManualMode ? CupertinoColors.activeBlue : null,
          ),
        ),
        middle: const Text('하드웨어 설정'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isBleConnected
                  ? CupertinoIcons.bluetooth
                  : CupertinoIcons.xmark_circle,
              color: _isBleConnected
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.inactiveGray,
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _switchCamera,
              child: const Icon(CupertinoIcons.switch_camera),
            ),
          ],
        ),
      ),

      // ── 본문
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 카메라 프리뷰
          if (_controller == null ||
              !_controller!.value.isInitialized ||
              _isSwitching)
            Container(
              color: CupertinoColors.black,
              child: const Center(child: CupertinoActivityIndicator()),
            )
          else
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),

          // 얼굴 박스
          if (_controller != null &&
              _controller!.value.isInitialized &&
              !_isSwitching)
            CustomPaint(
              painter: _FacePainter(
                _faces,
                _controller!.value.previewSize!,
                MediaQuery.of(context).size,
                _controller!.description.lensDirection ==
                    CameraLensDirection.front,
              ),
            ),

          // 얼굴 비율 디버그
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '얼굴 비율: ${_currentFaceRatio.toStringAsFixed(3)}',
                style: const TextStyle(
                    color: CupertinoColors.white, fontSize: 14),
              ),
            ),
          ),

          // 수동 제어 버튼
          if (_isManualMode && _isBleConnected) _buildManualControls(),

          // 상태 메시지
          Positioned(
            bottom: bottomPad + 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                    color: CupertinoColors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 수동 제어 패널
  // --------------------------------------------------------------------------
  Widget _buildManualControls() {
    return Positioned(
      right: 20,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CupertinoColors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
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
    // STOP 버튼
    if (cmd == 'STOP') {
      return GestureDetector(
        onTap: () {
          LinearMotorController.instance.stop();
        },
        child: Icon(icon, color: CupertinoColors.white, size: 44),
      );
    }

    // UP / DOWN 버튼 (길게 누르는 동안 주기 명령)
    return GestureDetector(
      onTapDown: (_) {
        _manualControlTimer =
            Timer.periodic(const Duration(milliseconds: 100), (_) {
              if (cmd == 'UP') {
                LinearMotorController.instance.up();
              } else {
                LinearMotorController.instance.down();
              }
            });
      },
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
}

/// ---------------------------------------------------------------------------
/// 얼굴 바운딩 박스 & 랜드마크 Painter
/// ---------------------------------------------------------------------------
class _FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;
  final Size screen;
  final bool isFrontCamera;

  _FacePainter(this.faces, this.absoluteImageSize, this.screen,
      this.isFrontCamera);

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = CupertinoColors.activeGreen;

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = CupertinoColors.systemRed;

    if (absoluteImageSize.isEmpty) return;

    for (final Face face in faces) {
      final scaleX = screen.width /
          (isFrontCamera
              ? absoluteImageSize.height
              : absoluteImageSize.width);
      final scaleY = screen.height /
          (isFrontCamera
              ? absoluteImageSize.width
              : absoluteImageSize.height);

      double left   = face.boundingBox.left   * scaleX;
      double top    = face.boundingBox.top    * scaleY;
      double right  = face.boundingBox.right  * scaleX;
      double bottom = face.boundingBox.bottom * scaleY;

      if (isFrontCamera) {
        final tmpLeft  = screen.width - right;
        final tmpRight = screen.width - left;
        left  = tmpLeft;
        right = tmpRight;
      }

      // 바운딩 박스
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), boxPaint);

      // 랜드마크
      for (final type in FaceLandmarkType.values) {
        final lm = face.landmarks[type];
        if (lm == null) continue;
        final dx = isFrontCamera
            ? screen.width - (lm.position.x * scaleX)
            : (lm.position.x * scaleX);
        final dy = lm.position.y * scaleY;
        canvas.drawCircle(ui.Offset(dx, dy), 2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.faces != faces ||
          old.absoluteImageSize != absoluteImageSize ||
          old.screen != screen ||
          old.isFrontCamera != isFrontCamera;
}