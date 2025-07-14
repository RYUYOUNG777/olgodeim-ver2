import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile_page.dart'; // 새로 만든 프로필 수정 페이지 import
import 'login_page.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  Map<String, dynamic>? userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // 사용자 데이터를 불러오는 함수
  Future<void> _loadUserData() async {
    // 로딩 상태를 다시 true로 설정하여 새로고침 효과
    setState(() { _loading = true; });
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          userData = doc.data();
        });
      }
    }
    // 데이터 로드가 끝나면 로딩 상태를 false로 설정
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  // 로그아웃 함수 (변경 없음)
  Future<void> _logout() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('로그아웃 에러 무시: $e');
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      CupertinoPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  // <<<--- 여기가 새로 추가된 부분! ---
  // 프로필 수정 페이지로 이동하는 함수
  void _navigateToEditProfile() async {
    if (userData == null) return;

    // EditProfilePage로 이동하고, 결과값을 받음
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => EditProfilePage(userData: userData!),
      ),
    );

    // 만약 EditProfilePage에서 '저장'을 눌러 true를 반환했다면,
    // 마이페이지의 데이터를 새로고침합니다.
    if (result == true) {
      _loadUserData();
    }
  }
  // --- 여기까지 새로 추가된 부분! --->>>


  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('마이페이지')),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final user = _auth.currentUser;
    if (user == null || userData == null) {
      return const Center(
        child: Text('사용자 정보가 없습니다.', style: TextStyle(fontSize: 16)),
      );
    }

    return ListView( // 스크롤이 가능하도록 ListView 사용
      children: [
        // 사용자 정보 섹션
        CupertinoListSection.insetGrouped(
          header: const Text('사용자 정보'),
          children: [
            CupertinoListTile(
              title: const Text('이메일'),
              subtitle: Text(user.email ?? '없음'),
            ),
            CupertinoListTile(
              title: const Text('이름'),
              subtitle: Text(userData!['name'] ?? '미입력'),
            ),
            CupertinoListTile(
              title: const Text('나이'),
              subtitle: Text('${userData!['age'] ?? '미입력'}세'),
            ),
            CupertinoListTile(
              title: const Text('키'),
              subtitle: Text('${userData!['height'] ?? '미입력'} cm'),
            ),
            CupertinoListTile(
              title: const Text('몸무게'),
              subtitle: Text('${userData!['weight'] ?? '미입력'} kg'),
            ),
            // <<<--- 여기가 새로 추가된 부분! ---
            // 운동 경력 항목 추가
            CupertinoListTile(
              title: const Text('운동 경력'),
              subtitle: Text(userData!['experience'] ?? '미입력'),
            ),
            // --- 여기까지 새로 추가된 부분! --->>>
          ],
        ),
        // 계정 관리 섹션
        CupertinoListSection.insetGrouped(
          header: const Text('계정 관리'),
          children: [
            // <<<--- 여기가 새로 추가된 부분! ---
            // 프로필 수정 버튼 추가
            CupertinoListTile(
              title: const Text('프로필 수정', style: TextStyle(color: CupertinoColors.activeBlue)),
              trailing: const CupertinoListTileChevron(),
              onTap: _navigateToEditProfile,
            ),
            // --- 여기까지 새로 추가된 부분! --->>>
            CupertinoListTile(
              title: const Text('로그아웃', style: TextStyle(color: CupertinoColors.destructiveRed)),
              onTap: _logout,
            ),
          ],
        ),
      ],
    );
  }
}