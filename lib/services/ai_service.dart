import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/workout_report.dart';

class AIService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  GenerativeModel? _model;

  AIService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey != null && apiKey.isNotEmpty) {
      _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
    } else {
      print("오류: GEMINI_API_KEY가 .env 파일에 설정되지 않았습니다.");
    }
  }

  // --- 기존 AI 운동 분석 보고서 기능 (변경 없음) ---
  Future<void> generateAndSaveReport({
    required String workoutName,
    required int completedReps,
    required int targetSets,
    double? weight,
    required Duration workoutDuration,
    required List<Map<String, dynamic>> workoutData,
    required List<String> suggestions,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("오류: 로그인이 필요합니다.");
    if (_model == null) throw Exception("오류: AI 모델이 초기화되지 않았습니다. API 키를 확인하세요.");

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data();

    final prompt = _buildPrompt(
      workoutName: workoutName,
      reps: completedReps,
      duration: workoutDuration,
      suggestions: suggestions,
      userName: userData?['name'] ?? '사용자',
      userAge: userData?['age']?.toString(),
      userHeight: userData?['height']?.toString(),
      userWeight: userData?['weight']?.toString(),
    );

    final response = await _model!.generateContent([Content.text(prompt)]);
    final aiAnalysis = response.text ?? "AI 분석 결과를 생성하는 데 실패했습니다.";

    final reportRef = _firestore.collection('users').doc(user.uid).collection('workoutLogs').doc();
    final postureScore = _calculatePostureScore(workoutData);

    final newReport = WorkoutReport(
      id: reportRef.id,
      userId: user.uid,
      workoutName: workoutName,
      date: DateTime.now(),
      completedReps: completedReps,
      targetSets: targetSets,
      weight: weight,
      workoutDuration: workoutDuration.inSeconds,
      postureScore: postureScore,
      aiAnalysis: aiAnalysis,
    );

    await reportRef.set(newReport.toJson());
  }

  double _calculatePostureScore(List<Map<String, dynamic>> workoutData) {
    if (workoutData.isEmpty) return 0;
    int goodPostureCount = workoutData
        .where((data) => data['isGoodPosture'] == true)
        .length;
    return (goodPostureCount / workoutData.length) * 100;
  }

  String _buildPrompt({
    required String workoutName,
    required int reps,
    required Duration duration,
    required List<String> suggestions,
    required String userName,
    String? userAge,
    String? userHeight,
    String? userWeight,
  }) {
    String userInfoText = "";
    if (userAge != null) userInfoText += "- 나이: $userAge세\n";
    if (userHeight != null) userInfoText += "- 키: $userHeight cm\n";
    if (userWeight != null) userInfoText += "- 몸무게: $userWeight kg\n";

    return """
    당신은 사용자의 운동 파트너이자 전문 피트니스 코치 '올핏(AllFit)'입니다. 아래 제공된 사용자의 개인 정보와 운동 기록을 종합적으로 분석하고, 매우 친근하고 개인화된 전문가의 조언을 한국어로 작성해주세요.

    ### 사용자 정보
    - 이름: $userName
    $userInfoText

    ### 운동 정보
    - 운동 종류: $workoutName
    - 총 횟수: $reps 회
    - 총 시간: ${duration.inMinutes}분 ${duration.inSeconds % 60}초
    - 시스템이 제공한 간단 피드백: ${suggestions.join(", ")}

    ### 분석 보고서 작성 가이드라인
    1.  **개인화된 인사**: 반드시 사용자의 이름을 부르며 시작해주세요. (예: "OOO님, 오늘도 정말 멋진데요!")
    2.  **결과 요약**: 오늘의 운동 성과를 간략하게 요약해주세요.
    3.  **개인 맞춤형 심층 분석**: 제공된 사용자의 '나이, 키, 몸무게'와 '운동 정보'를 종합적으로 고려하여 깊이 있는 분석을 제공해주세요. 
        - (예시) "OO세의 나이를 고려했을 때, 이 정도 중량은 관절에 무리를 주지 않으면서 근성장을 유도하기에 아주 좋습니다."
        - (예시) "키와 몸무게를 보면 근력이 좋으신 편인데, 다음 세트에서는 조금 더 중량을 높여서 도전해보는 건 어떨까요?"
    4.  **성장을 위한 꿀팁**: 시스템 피드백을 바탕으로 자세를 교정하는 방법이나, 사용자의 신체 조건에 맞는 추가적인 운동 팁을 제안해주세요.
    5.  **따뜻한 마무리 응원**: "오늘도 OOO님의 열정 덕분에 저도 에너지를 얻어 가요!" 와 같이 긍정적인 메시지로 마무리해주세요.
    
    위 가이드라인에 따라, 사용자가 정말로 1:1 PT를 받은 것처럼 느낄 수 있도록 상세하고 전문적인 보고서를 작성해주세요.
    """;
  }

  // <<<--- 여기가 새로 추가된 부분! ---
  // 챗봇 응답을 받아오는 새로운 함수
  Future<String> getChatbotResponse({required String query}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("오류: 로그인이 필요합니다.");
    if (_model == null) throw Exception("오류: AI 모델이 초기화되지 않았습니다. API 키를 확인하세요.");

    // Firestore에서 사용자 개인 정보를 가져옵니다.
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data();

    // 사용자 정보와 질문을 바탕으로 AI에게 보낼 프롬프트를 생성합니다.
    final prompt = _buildChatPrompt(
      query: query,
      userName: userData?['name'] ?? '사용자',
      userAge: userData?['age']?.toString(),
      userHeight: userData?['height']?.toString(),
      userWeight: userData?['weight']?.toString(),
      userExperience: userData?['experience'],
    );

    // AI에게 분석을 요청하고 답변을 받습니다.
    final response = await _model!.generateContent([Content.text(prompt)]);
    return response.text ?? "죄송합니다. 답변을 생성하는 데 실패했습니다.";
  }

  // 챗봇을 위한 프롬프트(질문지)를 만드는 함수
  String _buildChatPrompt({
    required String query,
    required String userName,
    String? userAge,
    String? userHeight,
    String? userWeight,
    String? userExperience,
  }) {
    String userInfoText = "";
    if (userAge != null) userInfoText += "- 나이: $userAge세\n";
    if (userHeight != null) userInfoText += "- 키: $userHeight cm\n";
    if (userWeight != null) userInfoText += "- 몸무게: $userWeight kg\n";
    if (userExperience != null) userInfoText += "- 운동 경력: $userExperience\n";

    return """
    너는 대한민국 최고의 피트니스 전문 상담가이자 동기부여 전문가 '올핏(AllFit)'이야. 사용자의 개인 정보를 바탕으로, 반드시 전문가처럼 친절하고 상세하게 답변해야 해.

    ### 상담할 사용자 정보
    - 이름: $userName
    $userInfoText

    ### 사용자의 질문
    "$query"

    ### 답변 가이드라인
    1.  **개인화된 호칭**: 답변을 시작할 때 반드시 사용자의 이름인 "$userName님"을 부르며 친근하게 시작해.
    2.  **정보 기반의 전문적인 답변**: 제공된 사용자의 '나이, 키, 몸무게, 운동 경력'을 반드시 고려해서, 질문에 대한 구체적이고 전문적인 해결책이나 조언을 제공해. 일반적인 답변이 아닌, 이 사람만을 위한 맞춤형 답변을 해야 해.
    3.  **안전 우선**: 사용자의 건강과 안전을 최우선으로 고려해서 답변해. 특히 부상이나 통증과 관련된 질문에는 신중하게 접근하고, 필요하다면 전문가(의사 등)의 상담을 권유해.
    4.  **격려와 동기부여**: 답변 마지막에는 항상 사용자가 운동에 대한 흥미를 잃지 않도록 따뜻한 격려와 응원의 메시지를 포함해줘.

    위 가이드라인에 따라, $userName님에게 최고의 맞춤형 피트니스 상담을 제공해줘.
    """;
  }
// --- 여기까지 새로 추가된 부분! --->>>
}