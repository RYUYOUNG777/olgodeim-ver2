/*import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // WriteBuffer 사용
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:http/http.dart' as http;

// 홈 화면으로 이동하기 위한 import (경로는 상황에 맞게 수정하세요)
import '../screens/home_page.dart';

/// 데드리프트 자세 분석에 사용되는 데이터 구조
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

/// 힙 각도 계산
double computeHipAngle(PoseLandmark shoulder, PoseLandmark hip, PoseLandmark knee) {
  final dx1 = shoulder.x - hip.x, dy1 = shoulder.y - hip.y;
  final dx2 = knee.x - hip.x, dy2 = knee.y - hip.y;
  final dot = dx1 * dx2 + dy1 * dy2;
  final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
  final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
  if (mag1 * mag2 == 0) return 0;
  final angleRad = math.acos(dot / (mag1 * mag2));
  return angleRad * 180 / math.pi;
}

/// GPT 프롬프트 전송 → 피드백 문자열 받기
Future<String> getGPTFeedbackWithCustomPrompt(String prompt) async {
  print("입력 데이터: $prompt");
  final url = Uri.parse("https://api.openai.com/v1/chat/completions");
  final response = await http.post(
    url,
    headers: {
      "Content-Type": "application/json",
      // 실제 환경에서는 자신의 API 키로 교체하세요.
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

/// DeadliftAnalysisPage: 데드리프트 자세 분석 페이지
/// [targetRepCount]는 외부(운동 선택 페이지)에서 전달된 목표 횟수입니다.
class DeadliftAnalysisPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final int targetRepCount;
  const DeadliftAnalysisPage({Key? key, required this.cameras, required this.targetRepCount}) : super(key: key);

  @override
  _DeadliftAnalysisPageState createState() => _DeadliftAnalysisPageState();
}

class _DeadliftAnalysisPageState extends State<DeadliftAnalysisPage> {
  late CameraController _controller;
  PoseDetector? _poseDetector;
  bool _isDetecting = false;
  bool _isStarted = false;
  bool _analysisCompleted = false;

  // 카운트다운 관련 변수
  int _countdown = 5;
  Timer? _countdownTimer;

  // 실시간 피드백 / GPT 요약 피드백
  String _feedback = "";
  String? _gptFeedback;

  // 프레임별 데이터
  List<PoseData> _deadliftDataList = [];
  List<PoseData> _curlDataList = [];

  int _frameCount = 0;
  int _repCount = 0; // 데드리프트 반복 횟수
  String _repState = "up";

  DateTime? _wrongPostureStartTime;
  final FlutterTts _flutterTts = FlutterTts();

  // 피드백 메시지별 횟수 기록 (문제점 카운트)
  Map<String, int> _feedbackFrequency = {};
  int kneeTooStraightCount = 0; // "무릎 각도가 너무 펴져 있습니다"
  int kneeTooBentCount = 0;     // "무릎 각도가 너무 굽혀졌습니다"
  int hipForwardCount = 0;      // "상체가 너무 앞으로 숙여졌습니다"
  int hipBackwardCount = 0;     // "상체가 너무 뒤로 젖혀졌습니다"
  int goodCount = 0;            // "자세가 양호합니다."

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
      print("데드리프트 카메라 초기화 완료: 해상도=${_controller.value.previewSize}");
      // 카메라 초기화 후 바로 5초 카운트다운 시작
      _startCountdown();
    }).catchError((e) {
      print("데드리프트 카메라 초기화 실패: $e");
    });
    _poseDetector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
  }

  /// 5초 카운트다운 → 카운트 다운이 끝나면 바로 분석 시작 및 _isStarted true 설정
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

  /// 문제점 카운트 업데이트
  void _updateProblemCounts(String feedbackMsg) {
    if (feedbackMsg.contains("무릎 각도가 너무 펴져")) {
      kneeTooStraightCount++;
    }
    if (feedbackMsg.contains("무릎 각도가 너무 굽혀졌")) {
      kneeTooBentCount++;
    }
    if (feedbackMsg.contains("상체가 너무 앞으로")) {
      hipForwardCount++;
    }
    if (feedbackMsg.contains("상체가 너무 뒤로")) {
      hipBackwardCount++;
    }
    if (feedbackMsg.contains("자세가 양호합니다")) {
      goodCount++;
    }
  }

  /// 분석 시작
  void _startAnalysis() {
    setState(() {
      _analysisCompleted = false;
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
        final imageRotation = InputImageRotationValue.fromRawValue(widget.cameras.first.sensorOrientation)
            ?? InputImageRotation.rotation0deg;
        final inputImageFormat = InputImageFormat.nv21;
        final metadata = InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
        );
        final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
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
            feedbackMsg += "무릎 각도가 너무 펴져 있습니다. 좀 더 구부려주세요. ";
          } else if (avgKneeAngle < 90) {
            feedbackMsg += "무릎 각도가 너무 굽혀졌습니다. 조금 펴주세요. ";
          }
          if (avgHipAngle < 80) {
            feedbackMsg += "상체가 너무 앞으로 숙여졌습니다. 허리를 곧게 펴주세요. ";
          } else if (avgHipAngle > 100) {
            feedbackMsg += "상체가 너무 뒤로 젖혀졌습니다. 상체를 앞으로 기울이세요. ";
          }
          if (feedbackMsg.isEmpty) {
            feedbackMsg = "자세가 양호합니다.";
          }

          // 데드리프트 rep 카운팅
          if (_repState == "up" && avgHipAngle < 80) {
            _repState = "down";
          } else if (_repState == "down" && avgHipAngle > 100) {
            _repCount++;
            _repState = "up";
          }

          _feedbackFrequency.update(feedbackMsg, (value) => value + 1, ifAbsent: () => 1);
          _updateProblemCounts(feedbackMsg);

          setState(() {
            _feedback = feedbackMsg;
            _deadliftDataList.add(
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

          // 자동 분석 종료: 목표 횟수 달성 시
          if (widget.targetRepCount > 0 &&
              _repCount >= widget.targetRepCount &&
              !_analysisCompleted) {
            await _onStopPressed();
          }

          // 음성 피드백 (나쁜 자세가 3초 이상 지속되면)
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
        print("데드리프트 - Error processing image: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  /// 분석 종료 → GPT 호출, 피드백 라인 필터링 적용 후 최대 5줄 요약 (각 줄 1줄씩 번호 매김)
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

    // 피드백 라인 필터링 조건 적용
    const int maxLineLength = 100; // 필요에 따라 조정 가능
    final rawLines = gptResponse.split("\n");
    List<String> filteredLines = [];
    for (var line in rawLines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 특정 문구가 포함된 줄은 건너뜁니다.
      if (trimmed.contains("운동 자세를 개선하기 위해")) continue;
      // "개선사항" 또는 "칭찬할점"으로 시작하면 해당 접두어 제거
      if (trimmed.toLowerCase().startsWith("개선사항")) {
        trimmed = trimmed.replaceFirst(RegExp(r'개선사항[:：\s]*'), '');
      } else if (trimmed.toLowerCase().startsWith("칭찬할점")) {
        trimmed = trimmed.replaceFirst(RegExp(r'칭찬할점[:：\s]*'), '');
      }
      // "-"로 시작하면 "-"만 제거
      if (trimmed.startsWith("-")) {
        trimmed = trimmed.substring(1).trim();
      }
      // "…", "..."가 포함된 줄은 건너뜁니다.
      if (trimmed.contains("…") || trimmed.contains("...")) continue;
      // 지정된 최대 길이 초과 시 건너뜁니다.
      if (trimmed.length > maxLineLength) continue;
      filteredLines.add(trimmed);
    }

    // 문장이 종료되면 다음 줄로 넘어가도록 문장별로 분리
    List<String> sentenceLines = [];
    for (var line in filteredLines) {
      // 마침표, 느낌표, 물음표 뒤의 공백을 기준으로 문장 분리
      List<String> sentences = line.split(RegExp(r'(?<=[.!?])\s+'));
      for (var sentence in sentences) {
        String s = sentence.trim();
        if (s.isNotEmpty) {
          sentenceLines.add(s);
        }
      }
    }

    // 최대 5줄의 피드백에 대해 각 줄 앞에 번호를 붙입니다.
    final numberedFeedback = sentenceLines.take(5).toList().asMap().entries
        .map((entry) => "${entry.key + 1}. ${entry.value}")
        .join("\n");

    setState(() {
      _gptFeedback = numberedFeedback;
    });
  }





  /// 피드백 맵 → 문제점 문자열 요약
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

  /// 둥근 막대 그래프
  Widget _buildBarChart() {
    final items = [
      {"label": "무릎펴짐", "count": kneeTooStraightCount, "color": Colors.red},
      {"label": "무릎굽힘", "count": kneeTooBentCount, "color": Colors.orange},
      {"label": "앞숙임", "count": hipForwardCount, "color": Colors.blue},
      {"label": "뒤젖힘", "count": hipBackwardCount, "color": Colors.purple},
      {"label": "양호", "count": goodCount, "color": Colors.green},
    ];
    final maxVal = [
      kneeTooStraightCount,
      kneeTooBentCount,
      hipForwardCount,
      hipBackwardCount,
      goodCount
    ].reduce((a, b) => a > b ? a : b);
    const double maxBarHeight = 120.0;
    return SizedBox(
      height: 180,
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

  /// 전체 보고서 열기 → 팝업 (터치 시 닫힘)
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
  void _goToHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "데드리프트 분석",
      home: Scaffold(
        appBar: AppBar(title: const Text("데드리프트 분석")),
        body: _analysisCompleted
            ? Container(
          color: Colors.white,
          width: double.infinity,
          height: double.infinity,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  "< 데드리프트 횟수 : $_repCount / ${widget.targetRepCount} >",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildBarChart(),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _gptFeedback ?? "피드백이 없습니다.",
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
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
        )
            : Stack(
          children: [
            // 카메라 프리뷰 (분석 전/중)
            CameraPreview(_controller),
            // 실시간 피드백 (카메라 화면 상단)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
            // 카운트다운 오버레이: 분석 시작 전 (5초)
            if (!_isStarted)
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
            // 운동 횟수 및 운동 종료 버튼 (카운트다운 종료 후에만 표시)
            if (_isStarted && !_analysisCompleted)
              Positioned(
                left: 20,
                right: 20,
                bottom: 40,
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
                          "< 데드리프트 횟수 : $_repCount / ${widget.targetRepCount} >",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, color: Colors.black),
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
          ],
        ),
      ),
    );
  }
}

/*/// main() 함수: 데드리프트 분석 페이지만 실행
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  // 예시: 목표 횟수를 10으로 설정 (필요에 따라 조정)
  runApp(DeadliftAnalysisPage(cameras: cameras, targetRepCount: 10));
}
*/
*/