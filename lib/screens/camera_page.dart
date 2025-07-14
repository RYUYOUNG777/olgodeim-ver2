// lib/screens/camera_page.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;

import '../ml/pose_classifier.dart';
import 'workout_feedback_page.dart';

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
  bool _initialized = false;
  int _cameraIndex = 0;
  bool _isFlashVisible = false;

  late final PoseDetector _poseDetector;
  List<Pose> _poses = [];
  bool _isDetecting = false;

  late final PoseClassifier _classifier;
  bool _classifierReady = false;

  int _exerciseCount = 0;
  String _currentFeedback = '모델 초기화 중…';
  bool _isRecording = false;
  String _prevLabel = '';
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _poseDetector =
        PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
    _loadClassifier();
  }

  Future<void> _loadClassifier() async {
    _classifier = PoseClassifier();
    await _classifier.init();
    if (!mounted) return;
    setState(() {
      _classifierReady = true;
      _currentFeedback = '준비되면 운동을 시작하세요!';
    });
  }

  /* ── CAMERA ── */
  Future<void> _requestCameraPermission() async {
    if ((await Permission.camera.request()).isGranted) _initCamera(_cameraIndex);
  }

  Future<void> _initCamera(int index) async {
    await _controller?.dispose();
    final cams = await availableCameras();
    if (index >= cams.length) return;
    _controller = CameraController(cams[index], ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    setState(() => _initialized = true);
    _controller!.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage img) {
    if (_isDetecting || !_classifierReady) return;
    _detectPose(img);
  }

  Future<void> _detectPose(CameraImage img) async {
    _isDetecting = true;
    try {
      final input = InputImage.fromBytes(
        bytes: img.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: InputImageRotation.rotation270deg,
          format: InputImageFormat.nv21,
          bytesPerRow: img.planes[0].bytesPerRow,
        ),
      );

      final poses = await _poseDetector.processImage(input);
      if (poses.isNotEmpty) {
        final vec = _poseToVector(poses.first, img.width, img.height);
        final label = _classifier.predict(vec); // 'good' | 'bad'

        setState(() {
          _poses = poses;
          _currentFeedback = 'AI: $label';
          if (_isRecording && _prevLabel == 'bad' && label == 'good') {
            _exerciseCount++;
          }
          _prevLabel = label;
        });
      }
    } catch (_) {}
    _isDetecting = false;
  }

  /* ── 107-차원 특징 벡터 ── */
  List<double> _poseToVector(Pose pose, int w, int h) {
    final lm = pose.landmarks;
    final v = <double>[];

    for (final t in PoseLandmarkType.values) {
      final p = lm[t];
      if (p != null) {
        v..add(p.x / w)..add(p.y / h)..add(p.likelihood);
      } else {
        v..addAll([0, 0, 0]);
      }
    }

    Offset pt(PoseLandmarkType t) {
      final p = lm[t];
      return (p == null) ? Offset.zero : Offset(p.x / w, p.y / h);
    }

    double ang(Offset a, Offset b, Offset c) {
      if (a == Offset.zero || b == Offset.zero || c == Offset.zero) return 0;
      final v1 = a - b, v2 = c - b;
      final cos = (v1.dx * v2.dx + v1.dy * v2.dy) /
          (v1.distance * v2.distance + 1e-6);
      return math.acos(cos.clamp(-1, 1)) * 180 / math.pi;
    }

    final leftElbowAng  = ang(pt(PoseLandmarkType.leftShoulder),
        pt(PoseLandmarkType.leftElbow),
        pt(PoseLandmarkType.leftWrist));
    final rightElbowAng = ang(pt(PoseLandmarkType.rightShoulder),
        pt(PoseLandmarkType.rightElbow),
        pt(PoseLandmarkType.rightWrist));

    final leftSEdist  =
        (pt(PoseLandmarkType.leftShoulder) - pt(PoseLandmarkType.leftElbow)).distance;
    final rightSEdist =
        (pt(PoseLandmarkType.rightShoulder) - pt(PoseLandmarkType.rightElbow)).distance;

    final shoulderCtr = (pt(PoseLandmarkType.leftShoulder) +
        pt(PoseLandmarkType.rightShoulder)) / 2;
    final hipCtr      = (pt(PoseLandmarkType.leftHip) +
        pt(PoseLandmarkType.rightHip)) / 2;
    double spineAngle = 0;
    if (shoulderCtr != Offset.zero && hipCtr != Offset.zero) {
      spineAngle = math.atan2(
          hipCtr.dy - shoulderCtr.dy, hipCtr.dx - shoulderCtr.dx) *
          180 / math.pi;
    }

    final leftWrAlign  = ang(pt(PoseLandmarkType.leftWrist),
        pt(PoseLandmarkType.leftElbow),
        pt(PoseLandmarkType.leftShoulder));
    final rightWrAlign = ang(pt(PoseLandmarkType.rightWrist),
        pt(PoseLandmarkType.rightElbow),
        pt(PoseLandmarkType.rightShoulder));

    final shoulderDiff =
    (pt(PoseLandmarkType.leftShoulder).dy -
        pt(PoseLandmarkType.rightShoulder).dy).abs();

    v.addAll([
      leftElbowAng, rightElbowAng,
      leftSEdist,   rightSEdist,
      spineAngle,   leftWrAlign, rightWrAlign,
      shoulderDiff,
    ]);

    return v; // 107 floats
  }

  /* ── 운동 시작 / 완료 ── */
  void _startWorkout() {
    setState(() {
      _isRecording = true;
      _exerciseCount = 0;
      _prevLabel = '';
      _startTime = DateTime.now();
      _currentFeedback = '운동을 시작하세요!';
    });
  }

  void _completeWorkout() {
    if (!_isRecording) return;
    final dur = DateTime.now().difference(_startTime!);
    setState(() => _isRecording = false);
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
        ),
      ),
    );
  }

  /* ── 기타 Helper ── */
  Future<void> _capturePhoto() async {
    if (!(_controller?.value.isInitialized ?? false)) return;
    final img = await _controller!.takePicture();
    final dir = Directory('/storage/emulated/0/DCIM/Camera');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await img.saveTo(path.join(dir.path,
        'captured_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    setState(() => _isFlashVisible = true);
    await Future.delayed(const Duration(milliseconds: 300));
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
    _controller?.dispose();
    _poseDetector.close();
    _classifier.close();
    super.dispose();
  }

  /* ── UI ── */
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
                children: [
                  _buildPreviewWidget(),
                  if (_poses.isNotEmpty)
                    CustomPaint(
                      painter: PosePainter(
                        _poses,
                        Size(
                          _controller?.value.previewSize?.height ?? 1,
                          _controller?.value.previewSize?.width ?? 1,
                        ),
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
      color: CupertinoColors.systemBackground,
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
    if (!_initialized) return const Center(child: CupertinoActivityIndicator());
    return OrientationBuilder(
      builder: (_, __) {
        return LayoutBuilder(
          builder: (ctx, cons) {
            return FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize!.height,
                height: _controller!.value.previewSize!.width,
                child: GestureDetector(
                  onTapDown: (d) => _onTapFocus(d, cons),
                  child: CameraPreview(_controller!),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CupertinoButton.filled(
            child: const Icon(CupertinoIcons.camera),
            onPressed: _capturePhoto,
          ),
          CupertinoButton.filled(
            child: Text(_isRecording ? '운동 완료' : '운동 시작'),
            onPressed: _isRecording ? _completeWorkout : _startWorkout,
          ),
          CupertinoButton(
            child: const Text('이전 화면'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

/* ── PosePainter ── */
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  PosePainter(this.poses, this.imageSize);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = CupertinoColors.systemGreen
      ..strokeWidth = 3;
    final dot = Paint()
      ..color = CupertinoColors.systemRed
      ..style = PaintingStyle.fill;

    for (final pose in poses) {
      pose.landmarks.forEach((t, lm) {
        if (lm.likelihood > 0.5) {
          canvas.drawCircle(
              Offset(lm.x * size.width / imageSize.width,
                  lm.y * size.height / imageSize.height),
              4, dot);
        }
      });

      for (final c in _conn) {
        final p1 = pose.landmarks[c[0]];
        final p2 = pose.landmarks[c[1]];
        if (p1 != null && p2 != null && p1.likelihood > 0.5 && p2.likelihood > 0.5) {
          canvas.drawLine(
              Offset(p1.x * size.width / imageSize.width,
                  p1.y * size.height / imageSize.height),
              Offset(p2.x * size.width / imageSize.width,
                  p2.y * size.height / imageSize.height),
              line);
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
