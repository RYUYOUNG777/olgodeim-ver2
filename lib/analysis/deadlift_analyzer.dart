import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../screens/camera_page.dart';

class DeadliftAnalyzer implements ExerciseAnalyzer {
  String _repState = "up";
  final Map<String, int> _feedbackFrequency = {};

  double _getAngle(PoseLandmark first, PoseLandmark mid, PoseLandmark last) {
    // ... (위의 스쿼트 분석기와 동일)
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
    // ... (이전 데드리프트 분석기 코드와 동일)
    return ["데드리프트 분석 중...", false]; // 임시
  }
}