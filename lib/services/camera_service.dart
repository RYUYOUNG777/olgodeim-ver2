import 'package:camera/camera.dart';

class CameraService {
  /// 기기에 있는 카메라 목록 반환
  Future<List<CameraDescription>> getAvailableCameras() async {
    return availableCameras();
  }

  /// 주어진 카메라 설명으로 CameraController 초기화
  Future<CameraController> initializeCamera(CameraDescription description) async {
    CameraController controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    return controller;
  }
}
