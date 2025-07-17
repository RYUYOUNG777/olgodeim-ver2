// lib/analysis/deadlift_analyzer.dart
import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../screens/camera_page.dart';

class DeadliftAnalyzer implements ExerciseAnalyzer {
  String _repState = "up";
  final Map<String, int> _feedbackFrequency = {};
  int _stateCounter = 0;

  // [수정] 3프레임 -> 2프레임. 느린 동작 인식을 위해 임계값 완화
  final int _stateThreshold = 2;

  List<String> _lastPostureFeedback = [];

  double _getAngle(PoseLandmark first, PoseLandmark mid, PoseLandmark last) {
    final dx1 = first.x - mid.x, dy1 = first.y - mid.y;
    final dx2 = last.x - mid.x, dy2 = last.y - mid.y;
    final dot = dx1 * dx2 + dy1 * dy2;
    final mag1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
    final mag2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
    if (mag1 * mag2 == 0) return 0;
    final angleRad = math.acos(dot / (mag1 * mag2));
    return angleRad * 180 / math.pi;
  }

  @override
  String getReport() {
    if (_feedbackFrequency.isEmpty) return "분석 데이터가 없습니다.";
    final sortedEntries = _feedbackFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String summary = "자주 나온 피드백:\n";
    for (final entry in sortedEntries.take(3)) {
      summary += "- ${entry.key} (${entry.value}회)\n";
    }
    return summary;
  }

  @override
  List<Object> analyze(Pose pose) {
    bool didCount = false;
    String feedbackMsg = "자세를 잡아주세요.";
    final landmarks = pose.landmarks;

    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftHip == null || rightHip == null || leftKnee == null || rightKnee == null || leftAnkle == null || rightAnkle == null || leftShoulder == null || rightShoulder == null) {
      return [feedbackMsg, didCount, 180.0];
    }

    final avgKneeAngle = (_getAngle(leftHip, leftKnee, leftAnkle) + _getAngle(rightHip, rightKnee, rightAnkle)) / 2;
    final avgHipAngle = (_getAngle(leftShoulder, leftHip, leftKnee) + _getAngle(rightShoulder, rightHip, rightKnee)) / 2;

    List<String> currentPostureFeedback = [];

    if (avgHipAngle < 140 && avgKneeAngle > 145) {
      currentPostureFeedback.add("허리를 펴고 엉덩이를 낮추세요.");
    }

    if (avgKneeAngle < 130) {
      currentPostureFeedback.add("무릎을 너무 많이 굽혔습니다.");
    }

    if (avgHipAngle < 120) {
      if (_repState == "up") {
        _stateCounter++;
        if (_stateCounter >= _stateThreshold) {
          _repState = "down";
          _lastPostureFeedback = currentPostureFeedback;
          _stateCounter = 0;
        }
      }
    } else if (avgHipAngle > 165) {
      if (_repState == "down") {
        _stateCounter++;
        if (_stateCounter >= _stateThreshold) {
          _repState = "up";
          didCount = true;
          _stateCounter = 0;
        }
      }
    } else {
      _stateCounter = 0;
    }

    if (didCount) {
      if (_lastPostureFeedback.isEmpty) {
        feedbackMsg = "완벽합니다!";
      } else {
        feedbackMsg = _lastPostureFeedback.join(", ");
        for (var feedback in _lastPostureFeedback) {
          _feedbackFrequency.update(feedback, (value) => value + 1, ifAbsent: () => 1);
        }
      }
    } else {
      if (currentPostureFeedback.isNotEmpty) {
        feedbackMsg = currentPostureFeedback.join(", ");
      } else if (_repState == "down") {
        feedbackMsg = "좋습니다, 그대로 올라오세요.";
      } else {
        feedbackMsg = "자세를 잡고 내려가세요.";
      }
    }

    return [feedbackMsg, didCount, avgHipAngle];
  }
}