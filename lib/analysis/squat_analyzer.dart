import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../screens/camera_page.dart';

class SquatAnalyzer implements ExerciseAnalyzer {
  String _repState = "up";
  final Map<String, int> _feedbackFrequency = {};
  int _stateCounter = 0;
  final int _stateThreshold = 4;

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
      return [feedbackMsg, didCount];
    }

    final leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle);
    final avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    String currentFeedback = "";
    if (avgKneeAngle > 160) {
      currentFeedback = "자세를 유지하고 내려가세요.";
    } else if (avgKneeAngle > 150) {
      currentFeedback += "더 깊게 내려가세요. ";
    } else if (avgKneeAngle < 60) {
      currentFeedback += "너무 깊게 앉았어요. ";
    }

    if (currentFeedback.isEmpty) {
      currentFeedback = "자세가 좋습니다!";
    }
    feedbackMsg = currentFeedback;

    if (feedbackMsg.isNotEmpty && feedbackMsg != "자세가 좋습니다!") {
      _feedbackFrequency.update(feedbackMsg.trim(), (value) => value + 1, ifAbsent: () => 1);
    }

    if (avgKneeAngle < 100) {
      if (_repState == "up") {
        _stateCounter++;
        if (_stateCounter >= _stateThreshold) {
          _repState = "down";
          _stateCounter = 0;
        }
      }
    } else if (avgKneeAngle > 160) {
      if (_repState == "down") {
        _stateCounter++;
        if (_stateCounter >= _stateThreshold) {
          _repState = "up";
          didCount = true;
          feedbackMsg = "완벽합니다!";
          _stateCounter = 0;
        }
      }
    } else {
      _stateCounter = 0;
    }

    return [feedbackMsg, didCount];
  }
}