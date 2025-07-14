/*import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // WriteBuffer 사용
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:http/http.dart' as http;

// 홈 화면 이동 (경로는 상황에 맞게 수정)
import '../screens/home_page.dart';

/// 자세 분석에 사용되는 데이터 구조
class PoseData {
  final int frameIndex;
  final double leftKneeX, leftKneeY;
  final double rightKneeX, rightKneeY;
  final double leftHipX, leftHipY;
  final double rightHipX, rightHipY;
  final double avgKneeAngle, avgHipAngle;

  PoseData({
    required this.frameIndex,
    required this.leftKneeX,
    required this.leftKneeY,
    required this.rightKneeX,
    required this.rightKneeY,
    required this.leftHipX,
    required this.leftHipY,
    required this.rightHipX,
    required this.rightHipY,
    required this.avgKneeAngle,
    required this.avgHipAngle,
  });
}

/// 무릎 각도 계산
double computeKneeAngle(PoseLandmark hip, PoseLandmark knee, PoseLandmark ankle) {
  final dx1 = hip.x - knee.x, dy1 = hip.y - knee.y;
  final dx2 = ankle.x - knee.x, dy2 = ankle.y - knee.y;
  final dot = dx1 * dx2 + dy1 * dy2;
  final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
  final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
  if (mag1 * mag2 == 0) return 0;
  final angleRad = math.acos(dot / (mag1 * mag2));
  return angleRad * 180 / math.pi;
}

/// 힙(엉덩이) 각도 계산
double computeHipAngle(
    PoseLandmark shoulder, PoseLandmark hip, PoseLandmark knee) {
  final dx1 = shoulder.x - hip.x, dy1 = shoulder.y - hip.y;
  final dx2 = knee.x - hip.x, dy2 = knee.y - hip.y;
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
      // 자신의 API 키로 교체하세요.
      "Authorization":
      "Bearer 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",
    },
    body: jsonEncode({
      "model": "gpt-3.5-turbo",
      "messages": [
        {
          "role": "system",
          "content":
          "당신은 전문 피트니스 코치입니다. 간결하고 정확한 피드백을 한국어로 제공합니다."
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

/// SquatAnalysisPage: 스쿼트 자세 분석 페이지
/// [targetRepCount]: 목표 횟수
class SquatAnalysisPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final int targetRepCount;

  const SquatAnalysisPage({
    Key? key,
    required this.cameras,
    required this.targetRepCount,
  }) : super(key: key);

  @override
  _SquatAnalysisPageState createState() => _SquatAnalysisPageState();
}

class _SquatAnalysisPageState extends State<SquatAnalysisPage> {
  late CameraController _controller;
  PoseDetector? _poseDetector;
  bool _isDetecting = false;
  bool _analysisCompleted = false;
  int _countdown = 5;
  Timer? _countdownTimer;
  bool _isStarted = false;

  String _feedback = "";
  String? _gptFeedback;
  List<PoseData> _squatDataList = [];

  int _frameCount = 0;
  int _repCount = 0;
  String _repState = "up";

  DateTime? _wrongPostureStartTime;
  final FlutterTts _flutterTts = FlutterTts();

  Map<String, int> _feedbackFrequency = {};
  int lowerCount = 0; // "더 낮게 내려가세요!"
  int deeperCount = 0; // "너무 깊게 내려갔어요!"
  int forwardCount = 0; // "앞으로 기울었어요!"
  int backwardCount = 0; // "뒤로 젖혀졌어요!"
  int goodCount = 0; // "자세가 양호합니다."

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
      print("스쿼트 카메라 초기화 완료: ${_controller.value.previewSize}");
      _startCountdown();
    }).catchError((e) {
      print("스쿼트 카메라 초기화 실패: $e");
    });
    _poseDetector =
        PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
  }

  /// 5초 카운트다운 후 자동 분석 시작
  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
          _isStarted = true;
          _startAnalysis();
        }
      });
    });
  }

  void _updateProblemCounts(String feedbackMsg) {
    if (feedbackMsg.contains("더 낮게 내려가세요")) {
      lowerCount++;
    }
    if (feedbackMsg.contains("너무 깊게 내려갔어요")) {
      deeperCount++;
    }
    if (feedbackMsg.contains("앞으로 기울었어요")) {
      forwardCount++;
    }
    if (feedbackMsg.contains("뒤로 젖혀졌어요")) {
      backwardCount++;
    }
    if (feedbackMsg.contains("자세가 양호합니다")) {
      goodCount++;
    }
  }

  void _startAnalysis() {
    print("스쿼트 분석 시작!");
    _controller.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;
      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final imageSize = Size(
          image.width.toDouble(),
          image.height.toDouble(),
        );
        final imageRotation =
            InputImageRotationValue.fromRawValue(
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
          final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
          final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
          final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
          final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
          final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
          final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
          final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
          final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

          double leftKneeAngle = 0, rightKneeAngle = 0;
          double leftHipAngle = 0, rightHipAngle = 0;
          if (leftHip != null && leftKnee != null && leftAnkle != null) {
            leftKneeAngle = computeKneeAngle(leftHip, leftKnee, leftAnkle);
          }
          if (rightHip != null && rightKnee != null && rightAnkle != null) {
            rightKneeAngle = computeKneeAngle(rightHip, rightKnee, rightAnkle);
          }
          if (leftShoulder != null && leftHip != null && leftKnee != null) {
            leftHipAngle = computeHipAngle(leftShoulder, leftHip, leftKnee);
          }
          if (rightShoulder != null && rightHip != null && rightKnee != null) {
            rightHipAngle = computeHipAngle(rightShoulder, rightHip, rightKnee);
          }

          final avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;
          final avgHipAngle = (leftHipAngle + rightHipAngle) / 2;

          String feedbackMsg = "";
          if (avgKneeAngle > 150) {
            feedbackMsg += "스쿼트가 충분히 깊지 않습니다. 더 낮게 내려가세요! ";
          } else if (avgKneeAngle < 60) {
            feedbackMsg += "너무 깊게 내려갔어요! 조금 일어나세요! ";
          }
          if (avgHipAngle < 70) {
            feedbackMsg += "앞으로 기울었어요! ";
          } else if (avgHipAngle > 120) {
            feedbackMsg += "뒤로 젖혀졌어요! ";
          }
          if (feedbackMsg.isEmpty) {
            feedbackMsg = "자세가 양호합니다.";
          }

          if (_repState == "up" && avgKneeAngle < 100) {
            _repState = "down";
          } else if (_repState == "down" && avgKneeAngle > 130) {
            _repCount++;
            _repState = "up";
          }

          if (widget.targetRepCount > 0 &&
              _repCount >= widget.targetRepCount &&
              !_analysisCompleted) {
            await _onStopPressed();
          }

          _feedbackFrequency.update(feedbackMsg, (val) => val + 1, ifAbsent: () => 1);
          _updateProblemCounts(feedbackMsg);

          setState(() {
            _feedback = feedbackMsg;
            _squatDataList.add(
              PoseData(
                frameIndex: _frameCount++,
                leftKneeX: leftKnee?.x ?? 0.0,
                leftKneeY: leftKnee?.y ?? 0.0,
                rightKneeX: rightKnee?.x ?? 0.0,
                rightKneeY: rightKnee?.y ?? 0.0,
                leftHipX: leftHip?.x ?? 0.0,
                leftHipY: leftHip?.y ?? 0.0,
                rightHipX: rightHip?.x ?? 0.0,
                rightHipY: rightHip?.y ?? 0.0,
                avgKneeAngle: avgKneeAngle,
                avgHipAngle: avgHipAngle,
              ),
            );
          });

          if (!feedbackMsg.contains("양호")) {
            if (_wrongPostureStartTime == null) {
              _wrongPostureStartTime = DateTime.now();
            } else if (DateTime.now().difference(_wrongPostureStartTime!).inSeconds >= 3) {
              await _flutterTts.speak(_feedback);
              _wrongPostureStartTime = null;
            }
          } else {
            _wrongPostureStartTime = null;
          }
        }
      } catch (e) {
        print("스쿼트 - Error processing image: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _onStopPressed() async {
    _controller.stopImageStream();
    setState(() {
      _analysisCompleted = true;
    });
    final summary = _generateFeedbackSummary(_feedbackFrequency);
    final prompt =
        "운동: 스쿼트. 총 ${_squatDataList.length} 프레임의 데이터가 수집되었습니다.\n"
        "$summary\n"
        "운동 자세에 대한 개선 사항과 칭찬할 점을 간단하게 피드백해 주세요.";
    final gptResponse = await getGPTFeedbackWithCustomPrompt(prompt);
    final rawLines = gptResponse.split("\n");
    List<String> processedLines = [];
    for (var line in rawLines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.toLowerCase().startsWith("운동 자세에 대한 개선 사항")) {
        trimmed =
            trimmed.replaceFirst(RegExp(r'운동 자세에 대한 개선 사항[:：]?'), '').trim();
      }
      if (trimmed.toLowerCase().startsWith("칭찬할 점")) {
        trimmed = trimmed.replaceFirst(RegExp(r'칭찬할 점[:：]?'), '').trim();
      }
      if (trimmed.startsWith("-")) {
        trimmed = trimmed.substring(1).trim();
      }
      if (trimmed.contains("...")) {
        trimmed = trimmed.split("...")[0].trim();
      }
      processedLines.add(trimmed);
    }
    final lines = processedLines.take(5).toList();
    String formattedFeedback = "";
    for (int i = 0; i < lines.length; i++) {
      formattedFeedback += "${i + 1}. ${lines[i]}\n";
    }
    setState(() {
      _gptFeedback = formattedFeedback.trim();
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

  Widget _buildBarChart() {
    final items = [
      {"label": "더 낮게", "count": lowerCount, "color": Colors.red},
      {"label": "너무 깊게", "count": deeperCount, "color": Colors.orange},
      {"label": "앞으로", "count": forwardCount, "color": Colors.blue},
      {"label": "뒤로", "count": backwardCount, "color": Colors.purple},
      {"label": "양호", "count": goodCount, "color": Colors.green},
    ];
    final maxVal = [
      lowerCount,
      deeperCount,
      forwardCount,
      backwardCount,
      goodCount
    ].reduce((a, b) => a > b ? a : b);
    const double maxBarHeight = 150;
    return SizedBox(
      height: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((item) {
          final count = item["count"] as int;
          final label = item["label"] as String;
          final color = item["color"] as Color;
          final barHeight = maxVal == 0 ? 0.0 : (count / maxVal) * maxBarHeight;
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

  void _goToHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "스쿼트 자세 분석",
      home: Scaffold(
        appBar: AppBar(title: const Text("스쿼트 자세 분석")),
        // 스크롤뷰 없이 전체 화면을 Container로 감싸고 Stack을 사용합니다.
        body: Container(
          height: MediaQuery.of(context).size.height,
          child: Stack(
            children: [
              // 카메라 프리뷰 (분석 완료 전)
              if (!_analysisCompleted) CameraPreview(_controller),

              // 5초 카운트다운 (분석 시작 전)
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

              // 실시간 피드백 (분석 중)
              if (_isStarted && !_analysisCompleted)
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _feedback,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Colors.black),
                    ),
                  ),
                ),

              // **카메라 위**에 위치하도록 top으로 조정한 "횟수"와 "운동 종료" 버튼
              if (_isStarted && !_analysisCompleted)
                Positioned(
                  // 원하는 높이로 조절 (예: top: 300)
                  // 값이 낮을수록 화면 상단쪽에, 높을수록 화면 하단쪽에 표시
                  top: 540,
                  left: 20,
                  right: 20,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "< 스쿼트 횟수 : $_repCount / ${widget.targetRepCount} >",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _onStopPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            "운동 종료",
                            style: TextStyle(fontSize: 16, color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 분석 완료 후 결과 화면
              if (_analysisCompleted)
                Center(
                  child: Container(
                    padding: const EdgeInsets.only(
                        top: 40, left: 16, right: 16, bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          "< 스쿼트 횟수 : $_repCount / ${widget.targetRepCount} >",
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _gptFeedback ?? "피드백이 없습니다.",
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, color: Colors.black),
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
                          onPressed: _goToHomePage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlue,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 24),
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
      ),
    );
  }
}
*/