import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfilePage({Key? key, required this.userData}) : super(key: key);

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late int _age;
  late int _height;
  late int _weight;
  late String _experience;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userData['name'] ?? '');
    _age = widget.userData['age'] ?? 25;
    _height = widget.userData['height'] ?? 175;
    _weight = widget.userData['weight'] ?? 70;
    _experience = widget.userData['experience'] ?? '초보';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() { _isLoading = true; });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'name': _nameController.text,
        'age': _age,
        'height': _height,
        'weight': _weight,
        'experience': _experience,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print("프로필 업데이트 오류: $e");
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('프로필 수정'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isLoading ? null : _updateProfile,
          child: _isLoading ? const CupertinoActivityIndicator() : const Text('저장'),
        ),
      ),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              _buildTextField(controller: _nameController, label: '이름'),
              const SizedBox(height: 24),
              _buildPickerSection(
                label: '나이',
                value: '$_age 세',
                onPressed: () => _showPicker('나이', 10, 100, _age, (newVal) => setState(() => _age = newVal)),
              ),
              const SizedBox(height: 24),
              _buildPickerSection(
                label: '키',
                value: '$_height cm',
                onPressed: () => _showPicker('키', 130, 220, _height, (newVal) => setState(() => _height = newVal)),
              ),
              const SizedBox(height: 24),
              // <<<--- 여기가 핵심 수정 부분! ---
              // 누락되었던 초기값 _weight를 추가했습니다.
              _buildPickerSection(
                label: '몸무게',
                value: '$_weight kg',
                onPressed: () => _showPicker('몸무게', 30, 150, _weight, (newVal) => setState(() => _weight = newVal)),
              ),
              // --- 여기까지 핵심 수정 부분! --->>>
              const SizedBox(height: 24),
              _buildPickerSection(
                label: '운동 경력',
                value: _experience,
                onPressed: () => _showExperiencePicker(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
          child: Text(label, style: const TextStyle(color: CupertinoColors.secondaryLabel)),
        ),
        CupertinoTextFormFieldRow(
          controller: controller,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '$label 항목을 입력해주세요.';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPickerSection({required String label, required String value, required VoidCallback onPressed}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
          child: Text(label, style: const TextStyle(color: CupertinoColors.secondaryLabel)),
        ),
        CupertinoListTile(
          title: Text(value, style: const TextStyle(fontSize: 16)),
          trailing: const Icon(CupertinoIcons.right_chevron, color: CupertinoColors.tertiaryLabel),
          onTap: onPressed,
          backgroundColor: CupertinoColors.secondarySystemGroupedBackground,
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        ),
      ],
    );
  }

  void _showPicker(String title, int start, int end, int initialValue, ValueChanged<int> onSelectedItemChanged) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: CupertinoPicker(
          scrollController: FixedExtentScrollController(initialItem: initialValue - start),
          itemExtent: 40,
          onSelectedItemChanged: (index) => onSelectedItemChanged(start + index),
          children: List.generate(end - start + 1, (index) => Center(child: Text('${start + index}'))),
        ),
      ),
    );
  }

  void _showExperiencePicker() {
    final experiences = ['초보', '중수', '고수'];
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: CupertinoPicker(
          scrollController: FixedExtentScrollController(initialItem: experiences.indexOf(_experience)),
          itemExtent: 40,
          onSelectedItemChanged: (index) => setState(() => _experience = experiences[index]),
          children: experiences.map((e) => Center(child: Text(e))).toList(),
        ),
      ),
    );
  }
}