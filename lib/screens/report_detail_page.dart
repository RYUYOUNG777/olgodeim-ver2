import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../models/workout_report.dart';

class ReportDetailPage extends StatelessWidget {
  final WorkoutReport report;

  const ReportDetailPage({Key? key, required this.report}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(report.workoutName),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더: 운동 이름과 날짜
              Text(
                report.workoutName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('yyyy년 MM월 dd일 HH:mm').format(report.date),
                style: const TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: 24),

              // 운동 요약 정보
              _buildSummaryCard(),
              const SizedBox(height: 24),

              // AI 종합 분석 리포트
              _buildAiAnalysisCard(),
            ],
          ),
        ),
      ),
    );
  }

  // 운동 요약 정보를 보여주는 카드 위젯
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('완료 횟수', '${report.completedReps}회'),
          _buildStatItem('운동 시간', '${(report.workoutDuration / 60).floor()}분 ${report.workoutDuration % 60}초'),
          _buildStatItem('자세 점수', '${report.postureScore.toInt()}점', color: CupertinoColors.systemGreen),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color color = CupertinoColors.label}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: CupertinoColors.secondaryLabel),
        ),
      ],
    );
  }

  // AI 분석 내용을 보여주는 카드 위젯
  Widget _buildAiAnalysisCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.sparkles, color: CupertinoColors.systemYellow),
              SizedBox(width: 8),
              Text(
                'AI 종합 분석',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            report.aiAnalysis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.6, // 줄 간격
            ),
          ),
        ],
      ),
    );
  }
}