// lib/analysis/barbell_curl_analyzer.dart
import 'dart:math' as math;
import 'package:flutter/cupertino.dart'; // [수정] 이 줄을 추가하여 Offset 클래스를 불러옵니다.
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../screens/camera_page.dart';

class BarbellCurlAnalyzer implements ExerciseAnalyzer {
  String _repState = "down";
  final Map<String, int> _feedbackFrequency = {};
  int _stateCounter = 0;
  final int _stateThreshold = 4;
  List<String> _lastPostureFeedback = [];
  double? _initialTrunkAngle;

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

  double _getTorsoAngle(PoseLandmark leftShoulder, PoseLandmark rightShoulder, PoseLandmark leftHip, PoseLandmark rightHip) {
    final shoulderCenter = Offset((leftShoulder.x + rightShoulder.x) / 2, (leftShoulder.y + rightShoulder.y) / 2);
    final hipCenter = Offset((leftHip.x + rightHip.x) / 2, (leftHip.y + rightHip.y) / 2);
    final dy = hipCenter.dy - shoulderCenter.dy;
    final dx = hipCenter.dx - shoulderCenter.dx;
    return math.atan2(dy, dx) * 180 / math.pi + 90;
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

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];

    if (leftShoulder == null || rightShoulder == null || leftElbow == null || rightElbow == null || leftWrist == null || rightWrist == null || leftHip == null || rightHip == null) {
      return [feedbackMsg, didCount, 180.0];
    }

    final avgElbowAngle = (_getAngle(leftShoulder, leftElbow, leftWrist) + _getAngle(rightShoulder, rightElbow, rightWrist)) / 2;
    final torsoAngle = _getTorsoAngle(leftShoulder, rightShoulder, leftHip, rightHip);

    List<String> currentPostureFeedback = [];

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final leftElbowDrift = (leftElbow.x - leftShoulder.x).abs();
    final rightElbowDrift = (rightElbow.x - rightShoulder.x).abs();
    if (leftElbowDrift > shoulderWidth * 0.40 || rightElbowDrift > shoulderWidth * 0.40) {
      currentPostureFeedback.add("팔꿈치를 몸통에 고정하세요.");
    }

    if (_repState == "up" && _initialTrunkAngle != null) {
      if ((torsoAngle - _initialTrunkAngle!).abs() > 15) {
        currentPostureFeedback.add("허리 반동을 사용하지 마세요.");
      }
    }

    if (avgElbowAngle > 160 && _repState == "up") {
      currentPostureFeedback.add("팔을 완전히 펴세요.");
    } else if (avgElbowAngle <27) {
      currentPostureFeedback.add("과도하게 올렸습니다.");
    }

    if (currentPostureFeedback.isNotEmpty) {
      feedbackMsg = currentPostureFeedback.join(", ");
    } else {
      feedbackMsg = "자세가 좋습니다!";
    }

    if (currentPostureFeedback.isNotEmpty) {
      for (var feedback in currentPostureFeedback) {
        _feedbackFrequency.update(feedback, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    if (avgElbowAngle < 70) {
      if (_repState == "down") {
        _stateCounter++;
        if (_stateCounter >= _stateThreshold) {
          _repState = "up";
          _lastPostureFeedback = currentPostureFeedback;
          _initialTrunkAngle = torsoAngle;
          _stateCounter = 0;
        }
      }
    } else if (avgElbowAngle > 150) {
      if (_repState == "up") {
        _stateCounter++;
        if (_stateCounter >= _stateThreshold) {
          _repState = "down";
          didCount = true;
          _initialTrunkAngle = null;
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
      }
    }

    return [feedbackMsg, didCount, avgElbowAngle];
  }
}