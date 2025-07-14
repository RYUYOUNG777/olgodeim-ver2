// lib/screens/routine_content_page.dart
import 'package:flutter/cupertino.dart';
import 'package:final_graduation_work/data/workout_data.dart';

/// RoutineContentPage: 사용자가 생성한 루틴을 탭하면, 해당 루틴에 포함된 운동 목록과 이미지를 보여줍니다.
class RoutineContentPage extends StatelessWidget {
  final Map<String, dynamic> routine;
  const RoutineContentPage({super.key, required this.routine});

  @override
  Widget build(BuildContext context) {
    final List<dynamic> workouts = routine['workouts'] as List<dynamic>;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(routine['title']),
      ),
      child: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: workouts.length,
          itemBuilder: (context, index) {
            final workout = workouts[index] as String;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  buildWorkoutThumbnail(workout),
                  const SizedBox(width: 8),
                  Text(
                    workout,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
