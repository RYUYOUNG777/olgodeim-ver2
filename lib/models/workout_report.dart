import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutReport {
  final String id;
  final String userId;
  final String workoutName;
  final DateTime date;
  final int completedReps;
  final int targetSets;
  final double? weight;
  final int workoutDuration; // 초 단위
  final double postureScore;
  final String aiAnalysis; // AI가 생성한 분석 결과

  WorkoutReport({
    required this.id,
    required this.userId,
    required this.workoutName,
    required this.date,
    required this.completedReps,
    required this.targetSets,
    this.weight,
    required this.workoutDuration,
    required this.postureScore,
    required this.aiAnalysis,
  });

  // Firestore에 저장하기 위해 Map으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'workoutName': workoutName,
      'date': Timestamp.fromDate(date),
      'completedReps': completedReps,
      'targetSets': targetSets,
      'weight': weight,
      'workoutDuration': workoutDuration,
      'postureScore': postureScore,
      'aiAnalysis': aiAnalysis,
    };
  }

  // <<<--- 여기가 새로 추가된 부분! ---
  // Firestore의 Map 데이터를 WorkoutReport 객체로 변환하는 변환기
  factory WorkoutReport.fromMap(Map<String, dynamic> map) {
    return WorkoutReport(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      workoutName: map['workoutName'] ?? '알 수 없는 운동',
      date: (map['date'] as Timestamp).toDate(),
      completedReps: map['completedReps'] ?? 0,
      targetSets: map['targetSets'] ?? 0,
      weight: map['weight']?.toDouble(),
      workoutDuration: map['workoutDuration'] ?? 0,
      postureScore: map['postureScore']?.toDouble() ?? 0.0,
      aiAnalysis: map['aiAnalysis'] ?? '분석 내용이 없습니다.',
    );
  }
// --- 여기까지 새로 추가된 부분! --->>>
}