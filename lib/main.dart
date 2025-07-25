// main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'ui/CameraStream.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CameraStreamPage(cameras: cameras),
  ));
}
