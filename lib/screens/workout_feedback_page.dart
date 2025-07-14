import 'package:flutter/cupertino.dart';
import '../services/ai_service.dart'; // 방금 만든 AI 서비스를 import 합니다.

// StatefulWidget으로 변경하여 로딩 상태 등을 관리할 수 있게 합니다.
class WorkoutFeedbackPage extends StatefulWidget {
  final String workoutName;
  final int completedReps;
  final int targetSets;
  final double? weight;
  final List<Map<String, dynamic>> workoutData;
  final Duration workoutDuration;

  const WorkoutFeedbackPage({
    Key? key,
    required this.workoutName,
    required this.completedReps,
    required this.targetSets,
    this.weight,
    required this.workoutData,
    required this.workoutDuration,
  }) : super(key: key);

  @override
  State<WorkoutFeedbackPage> createState() => _WorkoutFeedbackPageState();
}

class _WorkoutFeedbackPageState extends State<WorkoutFeedbackPage> {
  final AIService _aiService = AIService();
  bool _isLoading = false; // AI가 분석하는 동안 로딩 애니메이션을 보여주기 위한 변수

  // 개선사항 목록을 생성하는 로직 (기존 위젯 빌드 함수에서 분리)
  List<String> _getImprovementSuggestions() {
    List<String> suggestions = [];
    int goodPostureCount = 0;
    for (var data in widget.workoutData) {
      if (data['isGoodPosture'] == true) goodPostureCount++;
    }
    double postureScore = widget.workoutData.isNotEmpty
        ? (goodPostureCount / widget.workoutData.length) * 100
        : 0;

    if (postureScore < 60) {
      suggestions.add('자세 교정이 필요합니다. 더 천천히 정확한 동작으로 운동하세요.');
    } else if (postureScore < 80) {
      suggestions.add('좋은 자세입니다! 조금 더 정확성을 높여보세요.');
    } else {
      suggestions.add('완벽한 자세입니다! 이 자세를 유지하세요.');
    }

    switch (widget.workoutName.toLowerCase()) {
      case 'squat':
      case '스쿼트':
        suggestions.add('무릎이 발끝을 넘지 않도록 주의하세요.');
        suggestions.add('허리를 곧게 펴고 내려가세요.');
        break;
      case 'deadlift':
      case '데드리프트':
        suggestions.add('허리를 곧게 펴고 엉덩이부터 올라오세요.');
        suggestions.add('바벨을 몸에 가깝게 유지하세요.');
        break;
      case 'curl':
      case '이두컬':
        suggestions.add('팔꿈치 위치를 고정하고 천천히 움직이세요.');
        suggestions.add('어깨와 등은 고정한 채로 운동하세요.');
        break;
    }
    return suggestions;
  }

  // 'AI 분석 보고서 저장' 버튼을 눌렀을 때 실행될 함수
  void _handleSaveReport() async {
    setState(() {
      _isLoading = true; // 로딩 시작 (버튼이 로딩 아이콘으로 바뀜)
    });

    try {
      // AI 서비스 호출
      await _aiService.generateAndSaveReport(
        workoutName: widget.workoutName,
        completedReps: widget.completedReps,
        targetSets: widget.targetSets,
        weight: widget.weight,
        workoutDuration: widget.workoutDuration,
        workoutData: widget.workoutData,
        suggestions: _getImprovementSuggestions(),
      );

      // 성공 시 팝업 알림
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('저장 완료'),
            content: const Text('AI 분석 보고서가 라이브러리에 안전하게 저장되었습니다.'),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('확인'),
                onPressed: () {
                  // 팝업 닫고 홈으로 이동
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 실패 시 오류 팝업 알림
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('오류 발생'),
            content: Text('보고서를 저장하는 중 문제가 발생했습니다.\n네트워크 상태를 확인하거나 잠시 후 다시 시도해주세요.\n\n오류: ${e.toString()}'),
            actions: [
              CupertinoDialogAction(
                child: const Text('확인'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } finally {
      // 성공/실패 여부와 관계없이 로딩 종료
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('운동 분석 결과'),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompletionHeader(),
              const SizedBox(height: 24),
              _buildWorkoutStats(),
              const SizedBox(height: 24),
              _buildPostureAnalysis(),
              const SizedBox(height: 24),
              _buildImprovementSuggestionsWidget(),
              const SizedBox(height: 24),
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  // --- 아래부터는 기존 UI 코드입니다 (StatefulWidget에 맞게 widget. 으로 접근) ---

  Widget _buildCompletionHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [CupertinoColors.systemBlue, CupertinoColors.systemPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: CupertinoColors.white,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            '🎉 ${widget.workoutName} 완료!',
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '총 ${widget.completedReps}회 수행',
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutStats() {
    final minutes = widget.workoutDuration.inMinutes;
    final seconds = widget.workoutDuration.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 운동 통계',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('완료 횟수', '${widget.completedReps}회'),
              _buildStatItem('목표 세트', '${widget.targetSets}세트'),
              _buildStatItem('운동 시간', '${minutes}m ${seconds}s'),
              if (widget.weight != null) _buildStatItem('중량', '${widget.weight}kg'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: CupertinoColors.systemBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: CupertinoColors.systemGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildPostureAnalysis() {
    int goodPostureCount = 0;
    int totalAnalysis = widget.workoutData.length;
    double averageAngle = 0;

    for (var data in widget.workoutData) {
      if (data['isGoodPosture'] == true) goodPostureCount++;
      if (data['angle'] != null) averageAngle += data['angle'];
    }

    if (totalAnalysis > 0) {
      averageAngle = averageAngle / totalAnalysis;
    }

    double postureScore = totalAnalysis > 0 ? (goodPostureCount / totalAnalysis) * 100 : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎯 자세 분석',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '자세 정확도: ${postureScore.toInt()}%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey4,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: postureScore / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            color: postureScore >= 80 ? CupertinoColors.systemGreen :
                            postureScore >= 60 ? CupertinoColors.systemYellow :
                            CupertinoColors.systemRed,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('올바른 자세: $goodPostureCount/$totalAnalysis회'),
          const SizedBox(height: 4),
          if (averageAngle > 0)
            Text('평균 각도: ${averageAngle.toInt()}°'),
        ],
      ),
    );
  }

  Widget _buildImprovementSuggestionsWidget() {
    final suggestions = _getImprovementSuggestions();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💡 개선 사항',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...suggestions.map((suggestion) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text(
                    suggestion,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            // 로딩 중일 때는 버튼을 비활성화하고, 로딩이 아닐 때만 _handleSaveReport 함수를 실행
            onPressed: _isLoading ? null : _handleSaveReport,
            child: _isLoading
                ? const CupertinoActivityIndicator() // 로딩 중일 때는 동그란 로딩 아이콘 표시
                : const Text('AI 분석 보고서 저장'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            child: const Text('다시 운동하기'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            child: const Text('홈으로 돌아가기'),
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          ),
        ),
      ],
    );
  }
}