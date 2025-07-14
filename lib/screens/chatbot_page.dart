import 'package:flutter/cupertino.dart'; // <--- 여기가 오타가 있었던 부분입니다!
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/ai_service.dart'; // AI 서비스를 import 합니다.

// 채팅 메시지의 데이터 모델
class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _textController = TextEditingController();
  final AIService _aiService = AIService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 챗봇 시작 시, 환영 메시지를 추가합니다.
    _messages.add(ChatMessage(
      text: '안녕하세요! 운동에 대해 궁금한 점이 있다면 무엇이든 물어보세요. 회원님의 정보를 바탕으로 개인 맞춤형 답변을 드릴게요.',
      isUser: false,
    ));
  }

  // 메시지를 전송하는 함수
  Future<void> _sendMessage() async {
    final userMessage = _textController.text;
    if (userMessage.isEmpty) return;

    // 사용자가 보낸 메시지를 화면에 추가
    setState(() {
      _messages.add(ChatMessage(text: userMessage, isUser: true));
      _isLoading = true; // 로딩 시작
    });

    _textController.clear();

    try {
      // AI 서비스에 사용자의 질문을 보내고 답변을 받습니다.
      final aiResponse = await _aiService.getChatbotResponse(query: userMessage);
      // AI의 답변을 화면에 추가
      setState(() {
        _messages.add(ChatMessage(text: aiResponse, isUser: false));
      });
    } catch (e) {
      // 에러 발생 시, 에러 메시지를 화면에 추가
      setState(() {
        _messages.add(ChatMessage(text: '죄송합니다. 답변을 생성하는 중 오류가 발생했습니다.', isUser: false));
      });
      print("챗봇 응답 오류: $e");
    } finally {
      // 로딩 종료
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 채팅 메시지 목록
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                reverse: true, // 최신 메시지가 항상 아래에 보이도록 설정
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  // 최신 메시지부터 거꾸로 빌드
                  final message = _messages.reversed.toList()[index];
                  return _buildChatMessage(message);
                },
              ),
            ),
            // 로딩 중일 때 인디케이터 표시
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: CupertinoActivityIndicator(),
              ),
            // 메시지 입력창
            _buildMessageInputField(),
          ],
        ),
      ),
    );
  }

  // 채팅 말풍선을 만드는 위젯
  Widget _buildChatMessage(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: message.isUser
              ? CupertinoColors.activeBlue
              : CupertinoColors.secondarySystemFill,
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? CupertinoColors.white : CupertinoColors.label,
          ),
        ),
      ),
    );
  }

  // 메시지 입력창을 만드는 위젯
  Widget _buildMessageInputField() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemGrey6,
        border: Border(top: BorderSide(color: CupertinoColors.systemGrey4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _textController,
              placeholder: '메시지를 입력하세요...',
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8.0),
          CupertinoButton(
            onPressed: _sendMessage,
            child: const Icon(CupertinoIcons.arrow_up_circle_fill),
          ),
        ],
      ),
    );
  }
}