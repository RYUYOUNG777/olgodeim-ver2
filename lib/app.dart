import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'screens/login_page.dart';
import 'screens/user_details_page.dart';
import 'screens/main_tab_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: '올곧음 App',
      theme: const CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
      ),
      // 시작 페이지를 AuthWrapper로 설정
      home: const AuthWrapper(),
    );
  }
}

/// AuthWrapper: FirebaseAuth의 로그인 상태와 Firestore의 사용자 문서 유무에 따라 화면 분기
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    debugPrint('AuthWrapper build - FirebaseAuth 상태 감시 시작');
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 데이터 수신 대기 중: 로딩 표시
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CupertinoPageScaffold(
            child: Center(child: CupertinoActivityIndicator()),
          );
        }
        // 로그인되지 않은 경우 → LoginPage
        if (!snapshot.hasData || snapshot.data == null) {
          debugPrint('AuthWrapper: 로그인된 사용자 없음 → LoginPage 이동');
          return const LoginPage();
        }
        // 로그인된 경우 Firestore에서 사용자 문서 확인
        final user = snapshot.data!;
        debugPrint('AuthWrapper: 현재 사용자 UID=${user.uid}');
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, userDocSnapshot) {
            if (userDocSnapshot.connectionState == ConnectionState.waiting) {
              return const CupertinoPageScaffold(
                child: Center(child: CupertinoActivityIndicator()),
              );
            }
            final userDoc = userDocSnapshot.data;
            final docExists = (userDoc != null && userDoc.exists);
            if (!docExists) {
              debugPrint('AuthWrapper: Firestore 문서 없음 → UserDetailsPage로 이동');
              return const UserDetailsPage();
            }
            debugPrint('AuthWrapper: Firestore 문서 존재 → MainTabPage로 이동');
            return const MainTabPage();
          },
        );
      },
    );
  }
}
