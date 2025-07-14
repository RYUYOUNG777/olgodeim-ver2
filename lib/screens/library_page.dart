import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/workout_report.dart';
import 'report_detail_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isEditing = false;

  Future<void> _deleteReport(String reportId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('workoutLogs')
          .doc(reportId)
          .delete();
    } catch (e) {
      print("보고서 삭제 중 오류 발생: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Text(_isEditing ? '완료' : '편집'),
          onPressed: () {
            setState(() {
              _isEditing = !_isEditing;
            });
          },
        ),
      ),
      child: SafeArea(
        child: user == null
            ? const Center(child: Text('AI 리포트를 보려면 로그인이 필요합니다.'))
            : StreamBuilder<QuerySnapshot>(
          // <<<--- 여기가 핵심 수정 부분! ---
          // 복잡한 where 필터를 제거하고, 날짜순 정렬만 다시 요청합니다.
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('workoutLogs')
              .orderBy('date', descending: true)
              .snapshots(),
          // --- 여기까지 핵심 수정 부분! --->>>
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CupertinoActivityIndicator());
            }
            if (snapshot.hasError) {
              // 오류 메시지를 사용자에게 더 친절하게 보여줍니다.
              return Center(child: Text('오류가 발생했습니다.\n잠시 후 다시 시도해주세요.'));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                  child: Text(
                    '저장된 운동 기록이 없습니다.',
                    textAlign: TextAlign.center,
                  ));
            }

            // Firestore에서 가져온 모든 기록 중에서
            final reports = snapshot.data!.docs
                .map((doc) => doc.data() as Map<String, dynamic>)
            // aiAnalysis 필드가 있는 (AI 분석이 완료된) 기록만 앱에서 직접 골라냅니다.
                .where((data) => data.containsKey('aiAnalysis'))
                .map((data) => WorkoutReport.fromMap(data))
                .toList();

            // 만약 골라낸 AI 보고서가 없다면, 안내 메시지를 보여줍니다.
            if (reports.isEmpty) {
              return const Center(
                  child: Text(
                    '저장된 AI 분석 보고서가 없습니다.',
                    textAlign: TextAlign.center,
                  ));
            }

            return ListView.builder(
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return _buildReportTile(
                  report: report,
                  onTap: _isEditing ? null : () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => ReportDetailPage(report: report),
                      ),
                    );
                  },
                  onDelete: () => _deleteReport(report.id),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportTile({
    required WorkoutReport report,
    required VoidCallback? onTap,
    required VoidCallback onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onDelete,
                  child: const Icon(CupertinoIcons.minus_circle_fill, color: CupertinoColors.destructiveRed),
                ),
              ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.workoutName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('yyyy년 MM월 dd일').format(report.date),
                          style: const TextStyle(fontSize: 14, color: CupertinoColors.secondaryLabel),
                        ),
                        Text(
                          '자세 점수: ${report.postureScore.toInt()}점',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: report.postureScore >= 80
                                ? CupertinoColors.systemGreen
                                : CupertinoColors.systemOrange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (!_isEditing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(CupertinoIcons.right_chevron, color: CupertinoColors.tertiaryLabel),
              ),
          ],
        ),
      ),
    );
  }
}