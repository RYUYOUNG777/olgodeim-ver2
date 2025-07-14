/*import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // WriteBuffer 포함
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:http/http.dart' as http;

// 홈 화면으로 이동하기 위한 import (경로는 상황에 맞게 수정하세요)
import '../screens/home_page.dart';

/// 바벨 컬 데이터 모델
class BarbellCurlData {
  final int frameIndex;
  final double leftElbowAngle, rightElbowAngle;

  BarbellCurlData({
    required this.frameIndex,
    required this.leftElbowAngle,
    required this.rightElbowAngle,
  });
}

/// 팔꿈치 각도 계산 함수
double computeElbowAngle(
    PoseLandmark shoulder,
    PoseLandmark elbow,
    PoseLandmark wrist,
    ) {
  final dx1 = shoulder.x - elbow.x, dy1 = shoulder.y - elbow.y;
  final dx2 = wrist.x - elbow.x, dy2 = wrist.y - elbow.y;
  final dot = dx1 * dx2 + dy1 * dy2;
  final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
  final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
  if (mag1 * mag2 == 0) return 0;
  final angleRad = math.acos(dot / (mag1 * mag2));
  return angleRad * 180 / math.pi;
}

/// GPT 피드백 요청 함수
Future<String> getGPTFeedbackWithCustomPrompt(String prompt) async {
  print("입력 데이터: $prompt");
  final url = Uri.parse("https://api.openai.com/v1/chat/completions");
  final response = await http.post(
    url,
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer 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", // 자신의 API 키
    },
    body: jsonEncode({
      "model": "gpt-3.5-turbo",
      "messages": [
        {
          "role": "system",
          "content": "당신은 전문 피트니스 코치입니다. 간결하고 정확한 피드백을 한국어로 제공합니다."
        },
        {"role": "user", "content": prompt}
      ],
      "temperature": 0.7,
      "max_tokens": 2000,
    }),
  );
  if (response.statusCode == 200) {
    final body = utf8.decode(response.bodyBytes);
    final message = jsonDecode(body)["choices"][0]["message"]["content"];
    print("GPT 응답: $message");
    return message;
  } else {
    print("GPT API 호출 실패, 상태 코드: ${response.statusCode}");
    print("응답 본문: ${response.body}");
    return "피드백을 생성하는 데 실패했습니다.";
  }
}

/// 바벨컬 분석 페이지
class BarbellCurlAnalysisPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final int targetRepCount; // 외부에서 전달받은 목표 반복 횟수

  const BarbellCurlAnalysisPage({
    Key? key,
    required this.cameras,
    required this.targetRepCount,
  }) : super(key: key);

  @override
  _BarbellCurlAnalysisPageState createState() =>
      _BarbellCurlAnalysisPageState();
}

class _BarbellCurlAnalysisPageState extends State<BarbellCurlAnalysisPage> {
  late CameraController _controller;
  PoseDetector? _poseDetector;

  bool _isDetecting = false;       // 이미지 처리 중 여부
  bool _isStarted = false;         // 분석 시작 여부
  bool _analysisCompleted = false; // 분석 완료 여부

  String _feedback = "";           // 실시간 피드백
  String? _gptFeedback;            // GPT 최종 피드백

  // 바벨 컬 측정 데이터
  final List<BarbellCurlData> _curlDataList = [];
  int _frameCount = 0;
  int _repCount = 0;              // 반복 횟수
  String _repState = "up";

  DateTime? _wrongPostureStartTime;
  final FlutterTts _flutterTts = FlutterTts();

  // 피드백 빈도수
  Map<String, int> _feedbackFrequency = {};
  int tooStraightCount = 0;
  int tooBentCount = 0;
  int unbalancedCount = 0;
  int goodCount = 0;

  // 5초 카운트다운
  int _countdown = 5;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    // 카메라 초기화 완료 -> 카운트다운 시작
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
      print("바벨컬 카메라 초기화 완료");
      _startCountdown();
    }).catchError((e) {
      print("바벨컬 카메라 초기화 실패: $e");
    });

    _poseDetector =
        PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
  }

  /// 5초 카운트다운
  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
          _startAnalysis();
        }
      });
    });
  }

  /// 문제점 카운트
  void _updateProblemCounts(String msg) {
    if (msg.contains("팔이 너무 펴져")) {
      tooStraightCount++;
    }
    if (msg.contains("팔꿈치가 너무 많이 굽혀졌")) {
      tooBentCount++;
    }
    if (msg.contains("좌우 팔의 균형")) {
      unbalancedCount++;
    }
    if (msg.contains("자세가 양호합니다")) {
      goodCount++;
    }
  }

  /// 분석 시작
  void _startAnalysis() {
    setState(() {
      _isStarted = true;
      _gptFeedback = null;
    });

    _controller.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;
      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final imageSize = Size(image.width.toDouble(), image.height.toDouble());
        final imageRotation = InputImageRotationValue.fromRawValue(
          widget.cameras.first.sensorOrientation,
        ) ??
            InputImageRotation.rotation0deg;
        final inputImageFormat = InputImageFormat.nv21;

        final metadata = InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow:
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
        );

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: metadata,
        );

        final poses = await _poseDetector!.processImage(inputImage);
        if (poses.isNotEmpty) {
          final pose = poses.first;
          final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
          final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
          final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
          final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
          final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
          final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

          double leftElbowAngle = 0, rightElbowAngle = 0;
          if (leftShoulder != null && leftElbow != null && leftWrist != null) {
            leftElbowAngle =
                computeElbowAngle(leftShoulder, leftElbow, leftWrist);
          }
          if (rightShoulder != null && rightElbow != null && rightWrist != null) {
            rightElbowAngle =
                computeElbowAngle(rightShoulder, rightElbow, rightWrist);
          }

          final avgAngle = (leftElbowAngle + rightElbowAngle) / 2;
          String msg = "";

          if (avgAngle > 160) {
            msg += "팔이 너무 펴져 있습니다. 더 컬하세요. ";
          } else if (avgAngle < 30) {
            msg += "팔꿈치가 너무 많이 굽혀졌습니다. 과도한 컬입니다. ";
          }
          if ((leftElbowAngle - rightElbowAngle).abs() > 20) {
            msg += "좌우 팔의 균형을 맞추세요.";
          }
          if (msg.isEmpty) msg = "자세가 양호합니다.";

          // Rep 카운팅
          if (_repState == "up" && avgAngle < 60) {
            _repState = "down";
          } else if (_repState == "down" && avgAngle > 140) {
            _repCount++;
            _repState = "up";
          }

          // 목표 도달 시 종료
          if (widget.targetRepCount > 0 &&
              _repCount >= widget.targetRepCount &&
              !_analysisCompleted) {
            await _onStopPressed();
          }

          _feedbackFrequency.update(msg, (v) => v + 1, ifAbsent: () => 1);
          _updateProblemCounts(msg);

          setState(() {
            _feedback = msg;
            _curlDataList.add(
              BarbellCurlData(
                frameIndex: _frameCount++,
                leftElbowAngle: leftElbowAngle,
                rightElbowAngle: rightElbowAngle,
              ),
            );
          });

          // 3초 이상 나쁜 자세 -> 음성
          if (!msg.contains("양호")) {
            if (_wrongPostureStartTime == null) {
              _wrongPostureStartTime = DateTime.now();
            } else if (DateTime.now()
                .difference(_wrongPostureStartTime!)
                .inSeconds >=
                3) {
              await _flutterTts.speak(_feedback);
              _wrongPostureStartTime = null;
            }
          } else {
            _wrongPostureStartTime = null;
          }
        }
      } catch (e) {
        print("바벨컬 - Error: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  /// 분석 종료
  Future<void> _onStopPressed() async {
    _controller.stopImageStream();
    setState(() {
      _analysisCompleted = true;
    });
    final summary = _generateFeedbackSummary(_feedbackFrequency);
    final prompt = "운동: 바벨컬. 총 ${_curlDataList.length} 프레임의 데이터가 수집되었습니다.\n"
        "$summary\n"
        "운동 자세에 대한 개선 사항과 칭찬할 점을 간단하게 피드백해 주세요.";
    final gptResponse = await getGPTFeedbackWithCustomPrompt(prompt);
    final lines = gptResponse.split("\n");
    final summarizedFeedback = lines.take(5).join("\n");
    setState(() {
      _gptFeedback = summarizedFeedback;
    });
  }

  String _generateFeedbackSummary(Map<String, int> freq) {
    final sortedEntries = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sortedEntries.isEmpty) return "자세가 양호합니다.\n";

    String result = "";
    for (final entry in sortedEntries) {
      result += "${entry.key}\n";
    }
    return result;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller.dispose();
    _poseDetector?.close();
    super.dispose();
  }

  /// 막대 그래프
  Widget _buildBarChart() {
    final items = [
      {"label": "팔펴짐", "count": tooStraightCount, "color": Colors.red},
      {"label": "과도굽힘", "count": tooBentCount, "color": Colors.orange},
      {"label": "불균형", "count": unbalancedCount, "color": Colors.blue},
      {"label": "양호", "count": goodCount, "color": Colors.green},
    ];
    final maxVal = [
      tooStraightCount,
      tooBentCount,
      unbalancedCount,
      goodCount,
    ].reduce((a, b) => a > b ? a : b);

    const double maxBarHeight = 120.0;
    return SizedBox(
      height: 180,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((item) {
          final label = item["label"] as String;
          final color = item["color"] as Color;
          final count = item["count"] as int;
          final barHeight =
          maxVal == 0 ? 0.0 : (count / maxVal) * maxBarHeight;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 20,
                height: barHeight,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.black),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 전체 보고서 팝업
  void _showFullReport() {
    if (_gptFeedback == null) return;
    showDialog(
      context: Navigator.of(context).overlay!.context,
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _gptFeedback!,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 홈으로 이동
  void _goHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "바벨컬 분석",
      home: Scaffold(
        appBar: AppBar(title: const Text("바벨컬 분석")),
        body: Stack(
          children: [
            // 카메라 프리뷰 (분석 완료 전)
            if (!_analysisCompleted) CameraPreview(_controller),

            // 상단 실시간 피드백 (분석 완료 전)
            if (!_analysisCompleted)
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _feedback,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

            // 카운트다운 표시 (분석 전)
            if (!_isStarted && !_analysisCompleted)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontSize: 60,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // 하단 버튼/횟수 표시 (카운트다운 중에는 안 보이도록)
            if (_isStarted && !_analysisCompleted)
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Row(
                  children: [
                    // 좌측: (분석 중) 횟수 표시
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "< 바벨 컬 횟수 : $_repCount / ${widget.targetRepCount} >",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // 우측: 운동 종료 버튼
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _onStopPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          "운동 종료",
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 분석 완료 후 결과 화면
            if (_analysisCompleted)
              Positioned.fill(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        "< 바벨 컬 횟수 : $_repCount / ${widget.targetRepCount} >",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _buildBarChart(),
                      const SizedBox(height: 20),
                      // GPT 피드백
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _gptFeedback ?? "피드백이 없습니다.",
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style:
                          const TextStyle(fontSize: 16, color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _gptFeedback == null ? null : _showFullReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue,
                        ),
                        child: const Text(
                          "전체 보고서 열기",
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _goHome,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 24,
                          ),
                        ),
                        child: const Text(
                          "운동 종료 및 홈으로",
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
*/