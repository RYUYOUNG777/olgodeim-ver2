import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main_tab_page.dart';

class UserDetailsPage extends StatefulWidget {
  const UserDetailsPage({super.key});

  @override
  UserDetailsPageState createState() => UserDetailsPageState();
}

class UserDetailsPageState extends State<UserDetailsPage> {
  final PageController _pageController = PageController();

  // 상태 변수 (변경 없음)
  String _name = '';
  int _age = 25;
  String _gender = '남성';
  int _height = 175;
  int _weight = 70;
  String _experience = '초보';

  int _currentPage = 0;
  final int _totalPages = 6;

  // 데이터 저장 로직 (변경 없음)
  Future<void> _submitData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _name,
        'age': _age,
        'gender': _gender,
        'height': _height,
        'weight': _weight,
        'experience': _experience,
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        CupertinoPageRoute(builder: (_) => const MainTabPage()),
            (route) => false,
      );
    } catch (e) {
      print('Firestore 저장 오류: $e');
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.white,
      // <<<--- 수정 1/4: 키보드 오버플로우 방지 ---
      // 사용자가 이름을 입력할 때 키보드가 올라오면서 화면이 밀리는 현상을 방지합니다.
      resizeToAvoidBottomInset: true,
      // --- 여기까지 수정 --->>>
      child: SafeArea(
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() { _currentPage = page; });
                },
                children: [
                  _buildNamePage(),
                  _buildAgePage(),
                  _buildGenderPage(),
                  _buildHeightPage(),
                  _buildWeightPage(),
                  _buildExperiencePage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 각 단계를 보여주는 UI 위젯들

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalPages, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: MediaQuery.of(context).size.width / (_totalPages + 1),
            height: 4,
            decoration: BoxDecoration(
              color: _currentPage >= index
                  ? CupertinoColors.systemBlue
                  : CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNamePage() {
    return _buildPageContent(
      title: '닉네임을 입력해주세요',
      subtitle: '올곧음에서 사용하실 이름입니다.',
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: CupertinoTextField(
          placeholder: '이름',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, color: CupertinoColors.black),
          onChanged: (value) { _name = value; },
        ),
      ),
      onNext: () {
        if (_name.isNotEmpty) {
          _nextPage();
        }
      },
    );
  }

  // <<<--- 수정 2/4: 성별 선택 UI 수정 ---
  Widget _buildGenderPage() {
    return _buildPageContent(
      title: '성별을 선택해주세요',
      subtitle: '유저님의 정보를 바탕으로 운동 무게 추천 및 운동 소모칼로리가 계산됩니다.',
      // Row 안에서 Expanded를 사용하여 버튼들이 화면 너비를 똑같이 나눠 갖도록 수정
      content: Row(
        children: [
          Expanded(child: _buildSelectButton('남성', _gender)),
          const SizedBox(width: 20),
          Expanded(child: _buildSelectButton('여성', _gender)),
        ],
      ),
      onNext: _nextPage,
    );
  }
  // --- 여기까지 수정 --->>>

  Widget _buildAgePage() {
    return _buildPageContent(
      title: '나이를 알려주세요',
      subtitle: '유저님의 정보를 바탕으로 운동 무게 추천 및 운동 소모칼로리가 계산됩니다.',
      content: _buildPicker(
        start: 10,
        end: 100,
        initialItem: _age - 10,
        onSelectedItemChanged: (index) { _age = 10 + index; },
        suffix: '세',
      ),
      onNext: _nextPage,
    );
  }

  Widget _buildHeightPage() {
    return _buildPageContent(
      title: '키를 입력해주세요',
      subtitle: '유저님의 정보를 바탕으로 운동 무게 추천 및 운동 소모칼로리가 계산됩니다.',
      content: _buildPicker(
        start: 130,
        end: 220,
        initialItem: _height - 130,
        onSelectedItemChanged: (index) { _height = 130 + index; },
        suffix: 'cm',
      ),
      onNext: _nextPage,
    );
  }

  Widget _buildWeightPage() {
    return _buildPageContent(
      title: '몸무게를 입력해주세요',
      subtitle: '유저님의 정보를 바탕으로 운동 무게 추천 및 운동 소모칼로리가 계산됩니다.',
      content: _buildPicker(
        start: 30,
        end: 150,
        initialItem: _weight - 30,
        onSelectedItemChanged: (index) { _weight = 30 + index; },
        suffix: 'kg',
      ),
      onNext: _nextPage,
    );
  }

  Widget _buildExperiencePage() {
    return _buildPageContent(
      title: '자신의 운동 경력은 어떻게 되나요?',
      subtitle: '유저님의 정보를 바탕으로 운동 무게 추천 및 운동 소모칼로리가 계산됩니다.',
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSelectButton('초보', _experience),
          const SizedBox(height: 16),
          _buildSelectButton('중수', _experience),
          const SizedBox(height: 16),
          _buildSelectButton('고수', _experience),
        ],
      ),
      onNext: _submitData,
    );
  }

  // <<<--- 수정 3/4: 공통 선택 버튼 수정 ---
  // 고정된 너비를 제거하여 버튼이 유연하게 크기를 조절하도록 수정
  Widget _buildSelectButton(String value, String groupValue) {
    final isSelected = value == groupValue;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: isSelected ? CupertinoColors.systemBlue : CupertinoColors.systemGrey5,
      onPressed: () {
        setState(() {
          if (value == '남성' || value == '여성') {
            _gender = value;
          } else {
            _experience = value;
          }
        });
      },
      child: Text(
        value,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isSelected ? CupertinoColors.white : CupertinoColors.black,
        ),
      ),
    );
  }
  // --- 여기까지 수정 --->>>

  // <<<--- 수정 4/4: 공통 페이지 레이아웃 수정 ---
  // SingleChildScrollView를 추가하여 작은 화면에서도 모든 내용이 보이도록 수정
  Widget _buildPageContent({
    required String title,
    required String subtitle,
    required Widget content,
    required VoidCallback onNext,
  }) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // 최소 높이를 화면의 보이는 부분만큼으로 설정하여 '다음' 버튼이 항상 하단에 위치하도록 함
          minHeight: MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.top -
              MediaQuery.of(context).padding.bottom -
              72, // ProgressIndicator 높이 근사치
        ),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: CupertinoColors.black)),
                const SizedBox(height: 12),
                Text(subtitle, style: const TextStyle(fontSize: 16, color: CupertinoColors.systemGrey), textAlign: TextAlign.center),
                Expanded(
                  child: Center(
                    child: content,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: CupertinoColors.systemBlue,
                    onPressed: onNext,
                    child: Text(
                      _currentPage == _totalPages - 1 ? '완료' : '다음',
                      style: const TextStyle(color: CupertinoColors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
  // --- 여기까지 수정 --->>>

  Widget _buildPicker({
    required int start,
    required int end,
    required int initialItem,
    required ValueChanged<int> onSelectedItemChanged,
    String? suffix,
  }) {
    return SizedBox(
      height: 200,
      child: CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: initialItem),
        itemExtent: 48,
        onSelectedItemChanged: onSelectedItemChanged,
        children: List.generate(
          end - start + 1,
              (index) => Center(
            child: Text(
              '${start + index}${suffix ?? ''}',
              style: const TextStyle(fontSize: 28, color: CupertinoColors.black),
            ),
          ),
        ),
      ),
    );
  }
}