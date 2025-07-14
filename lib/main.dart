import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // 1. Flutter 엔진과 위젯 트리 바인딩 보장
  WidgetsFlutterBinding.ensureInitialized();

  // <<<--- 여기가 핵심 수정 부분! ---
  // 2. .env 파일을 불러와서 API 키 등 환경 변수 준비
  await dotenv.load(fileName: ".env");
  // --- 여기까지 핵심 수정 부분! --->>>

  // 3. Firebase 서비스 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 4. 앱 실행
  runApp(const MyApp());
}
