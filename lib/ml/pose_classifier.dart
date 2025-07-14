// lib/ml/pose_classifier.dart
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';

/// 107-차원 입력 & sigmoid 1-노드 출력 (good / bad)
class PoseClassifier {
  static const _modelPath = 'assets/models/pose_classifer_json.tflite';

  late final Interpreter _i;

  final int inputSize = 107;     // 99 + 8 파생 특징
  final double threshold = 0.5;  // 필요 시 0.45~0.55 조정

  Future<void> init() async {
    _i = await Interpreter.fromAsset(
      _modelPath,
      options: InterpreterOptions()..threads = 2,
    );
  }

  /// 107-차원 → 'good' | 'bad'
  String predict(List<double> x) {
    if (x.length != inputSize) {
      throw ArgumentError('Expected $inputSize floats, got ${x.length}');
    }

    final output = List.generate(1, (_) => [0.0]); // [1,1]
    _i.run([x], output);
    final double prob = output[0][0];

    return prob >= threshold ? 'good' : 'bad';
  }

  void close() => _i.close();
}
