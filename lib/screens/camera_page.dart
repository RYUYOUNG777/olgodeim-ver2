// lib/view/screens/camera_page.dart

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;

import '../analysis/squat_analyzer.dart';
import '../analysis/deadlift_analyzer.dart';
import '../analysis/barbell_curl_analyzer.dart';

// (이하 클래스 선언들은 이전과 동일)

abstract class ExerciseAnalyzer {
  List<Object> analyze(Pose pose);
  String getReport();
}


class CameraPage extends StatefulWidget {
  final String muscleGroup;
  final String tool;
  final String workoutName;
  final int setCount;
  final double? weight;

  const CameraPage({
    Key? key,
    required this.muscleGroup,
    required this.tool,
    required this.workoutName,
    required this.setCount,
    this.weight,
  }) : super(key: key);

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _initialized = false;
  int _cameraIndex = 1;
  bool _isFlashVisible = false;

  late final PoseDetector _poseDetector;
  List<Pose> _poses = [];
  bool _isDetecting = false;

  ExerciseAnalyzer? _analyzer;

  int _exerciseCount = 0;
  String _currentFeedback = '카메라를 초기화 중입니다…';
  bool _isRecording = false;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _poseDetector = PoseDetector(options: PoseDetectorOptions(model: PoseDetectionModel.base, mode: PoseDetectionMode.stream));
    _setAnalyzer();
  }

  void _setAnalyzer() {
    switch (widget.workoutName) {
      case '스쿼트':
        _analyzer = SquatAnalyzer();
        break;
      case '데드리프트':
        _analyzer = DeadliftAnalyzer();
        break;
      case '바벨 컬':
        _analyzer = BarbellCurlAnalyzer();
        break;
      default:
        _analyzer = null;
        _currentFeedback = '${widget.workoutName}은(는) 현재 자세 분석을 지원하지 않습니다.';
    }
    if (_analyzer != null) {
      _currentFeedback = '준비되면 운동을 시작하세요!';
    }
  }

  Future<void> _requestCameraPermission() async {
    if (await Permission.camera.request().isGranted) {
      _initCamera(_cameraIndex);
    }
  }

  Future<void> _initCamera(int index) async {
    await _controller?.dispose();
    final cams = await availableCameras();
    if (cams.isEmpty) {
      if(mounted) setState(() => _currentFeedback = '사용 가능한 카메라가 없습니다.');
      return;
    }
    _cameraIndex = index < cams.length ? index : 0;
    _camera = cams[_cameraIndex];

    _controller = CameraController(
      _camera!,
      ResolutionPreset.high,
      enableAudio: false,
      // imageFormatGroup을 제거해서 카메라 기본 포맷을 확인합니다.
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _initialized = true);
    _controller!.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage img) {
    if (_analyzer == null || _isDetecting) return;
    _detectAndAnalyzePose(img);
  }

  Future<void> _detectAndAnalyzePose(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    // 이 로그가 가장 중요합니다!
    print("📸 Camera Format Info: group=${image.format.group}, raw=${image.format.raw}");

    // 에러 방지를 위해 ML Kit 처리 로직을 잠시 비활성화
    /* try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final imageRotation = InputImageRotationValue.fromRawValue(_camera!.sensorOrientation);
      if (imageRotation == null) {
        _isDetecting = false;
        return;
      }

      final inputImageFormat = InputImageFormat.yuv420;

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );

      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isNotEmpty && _analyzer != null) {
        final analysisResult = _analyzer!.analyze(poses.first);
        final newFeedback = analysisResult[0] as String;
        final didCount = analysisResult[1] as bool;

        if (mounted) {
          setState(() {
            _poses = poses;
            _currentFeedback = newFeedback;
            if (_isRecording && didCount) {
              _exerciseCount++;
            }
          });
        }
      }
    } catch (e) {
      print("❌ 에러 발생: $e");
    }
    */

    _isDetecting = false;
  }

  void _startWorkout() {
    setState(() {
      _isRecording = true;
      _exerciseCount = 0;
      _startTime = DateTime.now();
      _currentFeedback = '운동을 시작하세요!';
    });
  }

  void _completeWorkout() async {
    if (!_isRecording || _analyzer == null) return;

    final dur = _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;
    setState(() => _isRecording = false);

    final summary = _analyzer!.getReport();
    final gptFeedback = summary;

    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => WorkoutFeedbackPage(
          workoutName: widget.workoutName,
          completedReps: _exerciseCount,
          targetSets: widget.setCount,
          weight: widget.weight,
          workoutData: const [],
          workoutDuration: dur,
          gptReport: gptFeedback,
        ),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    final img = await _controller!.takePicture();
    final dir = Directory('/storage/emulated/0/DCIM/Camera');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await img.saveTo(path.join(dir.path, 'captured_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    if(!mounted) return;
    setState(() => _isFlashVisible = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if(!mounted) return;
    setState(() => _isFlashVisible = false);
  }

  void _onTapFocus(TapDownDetails d, BoxConstraints c) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.globalToLocal(d.globalPosition);
    _controller?.setFocusPoint(Offset(pos.dx / c.maxWidth, pos.dy / c.maxHeight));
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar:
      CupertinoNavigationBar(middle: Text('${widget.workoutName} 운동')),
      child: SafeArea(
        child: Column(
          children: [
            _buildWorkoutHeader(),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreviewWidget(),
                  if (_poses.isNotEmpty)
                    CustomPaint(
                      painter: PosePainter(
                        _poses,
                        _controller?.value.previewSize ?? Size.zero,
                        _camera?.sensorOrientation ?? 90,
                      ),
                    ),
                  _buildFeedbackOverlay(),
                  AnimatedOpacity(
                    opacity: _isFlashVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      color: CupertinoColors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text('$_exerciseCount',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.systemBlue)),
              const Text('완료 횟수', style: TextStyle(fontSize: 12)),
            ],
          ),
          Column(
            children: [
              Text('${widget.setCount}',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.systemGreen)),
              const Text('목표 세트', style: TextStyle(fontSize: 12)),
            ],
          ),
          if (widget.weight != null)
            Column(
              children: [
                Text('${widget.weight}kg',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.systemOrange)),
                const Text('중량', style: TextStyle(fontSize: 12)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFeedbackOverlay() {
    return Positioned(
      bottom: 80,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBlue.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _currentFeedback,
          style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPreviewWidget() {
    if (!_initialized || _controller == null) return const Center(child: CupertinoActivityIndicator());
    return LayoutBuilder(
      builder: (ctx, cons) {
        final size = cons.biggest;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.height / (_controller!.value.aspectRatio),
                height: size.height,
                child: GestureDetector(
                  onTapDown: (d) => _onTapFocus(d, cons),
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CupertinoButton.filled(
            onPressed: _capturePhoto,
            child: const Icon(CupertinoIcons.camera),
          ),
          CupertinoButton.filled(
            onPressed: _isRecording ? _completeWorkout : _startWorkout,
            child: Text(_isRecording ? '운동 완료' : '운동 시작'),
          ),
          CupertinoButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('이전 화면'),
          ),
        ],
      ),
    );
  }
}

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final int imageRotation;

  PosePainter(this.poses, this.imageSize, this.imageRotation);

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final line = Paint()
      ..color = CupertinoColors.systemGreen
      ..strokeWidth = 3;
    final dot = Paint()
      ..color = CupertinoColors.systemRed
      ..style = PaintingStyle.fill;

    final double hRatio, vRatio;

    if (imageRotation == 90 || imageRotation == 270) {
      hRatio = size.width / imageSize.height;
      vRatio = size.height / imageSize.width;
    } else {
      hRatio = size.width / imageSize.width;
      vRatio = size.height / imageSize.height;
    }

    for (final pose in poses) {
      pose.landmarks.forEach((t, lm) {
        if (lm.likelihood > 0.5) {
          final offset = Offset(
            lm.x * hRatio,
            lm.y * vRatio,
          );
          canvas.drawCircle(offset, 4, dot);
        }
      });

      for (final c in _conn) {
        final p1 = pose.landmarks[c[0]];
        final p2 = pose.landmarks[c[1]];
        if (p1 != null && p2 != null && p1.likelihood > 0.5 && p2.likelihood > 0.5) {
          final offset1 = Offset(p1.x * hRatio, p1.y * vRatio);
          final offset2 = Offset(p2.x * hRatio, p2.y * vRatio);
          canvas.drawLine(offset1, offset2, line);
        }
      }
    }
  }

  static const _conn = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class WorkoutFeedbackPage extends StatelessWidget {
  final String workoutName;
  final int completedReps;
  final int targetSets;
  final double? weight;
  final List<Map<String, dynamic>> workoutData;
  final Duration workoutDuration;
  final String? gptReport;

  const WorkoutFeedbackPage({
    Key? key,
    required this.workoutName,
    required this.completedReps,
    required this.targetSets,
    this.weight,
    required this.workoutData,
    required this.workoutDuration,
    this.gptReport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('$workoutName 결과'),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('완료 횟수: $completedReps', style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle),
              const SizedBox(height: 20),
              if(gptReport != null)
                Text(gptReport!, style: CupertinoTheme.of(context).textTheme.textStyle),
              const SizedBox(height: 40),
              CupertinoButton.filled(
                child: const Text('확인'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}