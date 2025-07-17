// lib/screens/workout_selection_page.dart

import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:final_graduation_work/data/workout_data.dart';
import 'camera_page.dart'; // CameraPage로 이동하기 위해 import

// 분석 페이지 (분석 파일들은 lib/analysis/ 폴더 내에 위치)

class WorkoutSelectionPage extends StatefulWidget {
  const WorkoutSelectionPage({Key? key}) : super(key: key);

  @override
  State<WorkoutSelectionPage> createState() => _WorkoutSelectionPageState();
}

class _WorkoutSelectionPageState extends State<WorkoutSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  // ✅ [수정] 목표 횟수 컨트롤러 삭제
  // final TextEditingController _repCountInputController = TextEditingController();
  String _searchQuery = '';

  String? selectedGroup;
  String? selectedTool;
  String? selectedWorkout;

  int setCount = 3;
  double weight = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        if (_searchQuery.isNotEmpty) {
          selectedGroup = null;
          selectedTool = null;
          selectedWorkout = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    // ✅ [수정] 목표 횟수 컨트롤러의 dispose 삭제
    // _repCountInputController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // 🔻 데이터 정렬 및 헬퍼 함수
  // -----------------------------------------------------------------
  List<String> _sortWorkouts(List<String> workouts) {
    final fixedOrder = ["스쿼트", "데드리프트", "바벨 컬"];
    List<String> bookmarked = [];
    List<String> others = [];
    for (var workout in workouts) {
      String normalized = workout.replaceAll(" ", "");
      if (fixedOrder.any((item) => item.replaceAll(" ", "") == normalized)) {
        bookmarked.add(workout);
      } else {
        others.add(workout);
      }
    }
    bookmarked.sort((a, b) {
      int indexA = fixedOrder.indexWhere(
              (item) => item.replaceAll(" ", "") == a.replaceAll(" ", ""));
      int indexB = fixedOrder.indexWhere(
              (item) => item.replaceAll(" ", "") == b.replaceAll(" ", ""));
      return indexA.compareTo(indexB);
    });
    others.sort();
    return [...bookmarked, ...others];
  }

  bool _isBookmarked(String workout) {
    final bookmarks = ["스쿼트", "데드리프트", "바벨 컬"];
    String normalizedWorkout = workout.replaceAll(" ", "");
    return bookmarks.any((bm) => bm.replaceAll(" ", "") == normalizedWorkout);
  }

  List<String> _getSearchResults() {
    List<String> results = [];
    workoutData.forEach((group, toolMap) {
      toolMap.forEach((tool, workouts) {
        for (var workout in workouts) {
          if (workout.toLowerCase().contains(_searchQuery.toLowerCase())) {
            results.add(workout);
          }
        }
      });
    });
    return _sortWorkouts(results.toSet().toList());
  }

  List<String> _getAllWorkouts() {
    List<String> results = [];
    workoutData.forEach((group, toolMap) {
      toolMap.forEach((tool, workouts) {
        results.addAll(workouts);
      });
    });
    return _sortWorkouts(results.toSet().toList());
  }

  Future<void> _saveWorkoutLog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('사용자 로그인 상태가 아닙니다.');
      return;
    }

    String muscleGroup;
    if (selectedGroup != null) {
      muscleGroup = selectedGroup!;
    } else if (selectedWorkout != null) {
      muscleGroup = getMuscleGroupForWorkout(selectedWorkout!);
    } else {
      muscleGroup = '전체';
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('workoutLogs')
          .add({
        'date': FieldValue.serverTimestamp(),
        'muscleGroup': muscleGroup,
        'tool': selectedTool ?? '전체',
        'workoutName': selectedWorkout,
        'setCount': setCount,
        'weight': weight,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('운동 기록 저장 성공');
    } catch (e) {
      debugPrint('운동 기록 저장 에러: $e');
      rethrow;
    }
  }

  // -----------------------------------------------------------------
  // 🔻 UI Builder 메서드들
  // -----------------------------------------------------------------
  Widget _buildGroupSelector() {
    final groups = workoutData.keys.toList();
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          final isSelected = (group == selectedGroup);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: null,
              child: Text(
                group,
                style: TextStyle(
                  color: isSelected
                      ? CupertinoColors.activeBlue
                      : CupertinoColors.black,
                ),
              ),
              onPressed: () {
                setState(() {
                  if (selectedGroup == group) {
                    selectedGroup = null;
                    selectedTool = null;
                    selectedWorkout = null;
                  } else {
                    selectedGroup = group;
                    selectedTool = null;
                    selectedWorkout = null;
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolSelector(String group) {
    final tools = workoutData[group]!.keys.toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tools.map((tool) {
        final isSelected = (tool == selectedTool);
        return CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: null,
          child: Text(
            tool,
            style: TextStyle(
              color: isSelected
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.black,
            ),
          ),
          onPressed: () {
            setState(() {
              selectedTool = tool;
              selectedWorkout = null;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildWorkoutList(String group, String tool) {
    final workouts = workoutData[group]![tool]!;
    final sortedWorkouts = _sortWorkouts(workouts);
    return SizedBox(
      height: 400,
      child: ListView.builder(
        itemCount: sortedWorkouts.length,
        itemBuilder: (context, index) {
          final name = sortedWorkouts[index];
          final isSelected = (name == selectedWorkout);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              color: null,
              onPressed: () {
                setState(() {
                  selectedWorkout = name;
                });
              },
              child: Row(
                children: [
                  buildWorkoutThumbnail(name),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        color: isSelected
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.black,
                      ),
                    ),
                  ),
                  if (_isBookmarked(name))
                    const Icon(
                      CupertinoIcons.bookmark_fill,
                      color: CupertinoColors.systemYellow,
                    )
                  else if (isSelected)
                    const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: CupertinoColors.activeBlue,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkoutListAllByGroup(String group) {
    List<String> workouts = [];
    workoutData[group]!.forEach((tool, toolWorkouts) {
      workouts.addAll(toolWorkouts);
    });
    workouts = workouts.toSet().toList();
    final sortedWorkouts = _sortWorkouts(workouts);
    return SizedBox(
      height: 400,
      child: ListView.builder(
        itemCount: sortedWorkouts.length,
        itemBuilder: (context, index) {
          final name = sortedWorkouts[index];
          final isSelected = (name == selectedWorkout);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              color: null,
              onPressed: () {
                setState(() {
                  selectedWorkout = name;
                });
              },
              child: Row(
                children: [
                  buildWorkoutThumbnail(name),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        color: isSelected
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.black,
                      ),
                    ),
                  ),
                  if (_isBookmarked(name))
                    const Icon(
                      CupertinoIcons.bookmark_fill,
                      color: CupertinoColors.systemYellow,
                    )
                  else if (isSelected)
                    const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: CupertinoColors.activeBlue,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllWorkoutList() {
    final workouts = _getAllWorkouts();
    return SizedBox(
      height: 400,
      child: ListView.builder(
        itemCount: workouts.length,
        itemBuilder: (context, index) {
          final name = workouts[index];
          final isSelected = (name == selectedWorkout);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              color: null,
              onPressed: () {
                setState(() {
                  selectedWorkout = name;
                });
              },
              child: Row(
                children: [
                  buildWorkoutThumbnail(name),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        color: isSelected
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.black,
                      ),
                    ),
                  ),
                  if (_isBookmarked(name))
                    const Icon(
                      CupertinoIcons.bookmark_fill,
                      color: CupertinoColors.systemYellow,
                    )
                  else if (isSelected)
                    const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: CupertinoColors.activeBlue,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultList() {
    final results = _getSearchResults();
    return SizedBox(
      height: 500,
      child: ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final name = results[index];
          final isSelected = (name == selectedWorkout);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              color: null,
              onPressed: () {
                setState(() {
                  selectedWorkout = name;
                });
              },
              child: Row(
                children: [
                  buildWorkoutThumbnail(name),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        color: isSelected
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.black,
                      ),
                    ),
                  ),
                  if (_isBookmarked(name))
                    const Icon(
                      CupertinoIcons.bookmark_fill,
                      color: CupertinoColors.systemYellow,
                    )
                  else if (isSelected)
                    const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: CupertinoColors.activeBlue,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSetAndWeightInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('세트 수:', style: TextStyle(fontSize: 16)),
        Row(
          children: [
            CupertinoButton(
              child: const Icon(CupertinoIcons.minus_circle),
              onPressed: () {
                setState(() {
                  if (setCount > 1) setCount--;
                });
              },
            ),
            Text('$setCount 세트', style: const TextStyle(fontSize: 16)),
            CupertinoButton(
              child: const Icon(CupertinoIcons.add_circled),
              onPressed: () {
                setState(() {
                  setCount++;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('무게(kg):', style: TextStyle(fontSize: 16)),
        Row(
          children: [
            CupertinoButton(
              child: const Icon(CupertinoIcons.minus_circle),
              onPressed: () {
                setState(() {
                  if (weight > 0) weight--;
                });
              },
            ),
            Text('${weight.toInt()} kg',
                style: const TextStyle(fontSize: 16)),
            CupertinoButton(
              child: const Icon(CupertinoIcons.add_circled),
              onPressed: () {
                setState(() {
                  weight++;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  // ✅ [수정] 목표 횟수 입력 위젯(_buildRepCountInput) 전체 삭제

  // -----------------------------------------------------------------
  // 🔻 build()
  // -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bool showSearchResults = _searchQuery.isNotEmpty;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('운동 선택')),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: _searchController,
                placeholder: '운동 검색',
                padding: const EdgeInsets.all(12),
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
              const SizedBox(height: 16),
              if (!showSearchResults) ...[
                _buildGroupSelector(),
                const SizedBox(height: 16),
                if (selectedGroup != null) ...[
                  _buildToolSelector(selectedGroup!),
                  const SizedBox(height: 16),
                  if (selectedTool != null)
                    _buildWorkoutList(selectedGroup!, selectedTool!)
                  else
                    _buildWorkoutListAllByGroup(selectedGroup!)
                ] else
                  _buildAllWorkoutList(),
              ] else ...[
                _buildSearchResultList(),
              ],
              const SizedBox(height: 16),
              if (selectedWorkout != null) ...[
                _buildSetAndWeightInput(),
                // ✅ [수정] 목표 횟수 위젯 호출 및 여백(SizedBox) 삭제
              ],
              const SizedBox(height: 16),
              if (selectedWorkout != null)
                CupertinoButton.filled(
                  child: const Text('운동 추가하기'),
                  onPressed: () async {
                    if (selectedWorkout == null) return;

                    // ✅ [수정] 목표 횟수(repCount) 관련 로직 전체 삭제
                    try {
                      await _saveWorkoutLog();

                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => CameraPage(
                            muscleGroup: selectedGroup ??
                                getMuscleGroupForWorkout(selectedWorkout!),
                            tool: selectedTool ?? '전체',
                            workoutName: selectedWorkout!,
                            setCount: setCount,
                            weight: weight,
                            // ✅ [수정] targetReps 파라미터 전달 삭제
                          ),
                        ),
                      );
                    } catch (e) {
                      debugPrint('운동 추가하기 onPressed 에러: $e');
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}