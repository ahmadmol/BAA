import 'package:flutter/material.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    bool? isAuthenticated = prefs.getBool('isAuthenticated');

    if (isAuthenticated == true) {
      _goToCamera();
    } else {
      await _authenticateUser();
    }

    setState(() => _loading = false);
  }

  Future<void> _authenticateUser() async {
    try {
      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'يرجى استخدام بصمتك للدخول لأول مرة',
        options: const AuthenticationOptions(biometricOnly: true),
      );

      if (didAuthenticate) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isAuthenticated', true);
        _goToCamera();
      } else {
        setState(() => _failed = true);
      }
    } catch (e) {
      print("❌ خطأ في التحقق بالبصمة: $e");
      setState(() => _failed = true);
    }
  }

  void _goToCamera() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _failed
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('فشل التحقق بالبصمة'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _authenticateUser,
                        child: const Text('أعد المحاولة'),
                      ),
                    ],
                  )
                : const Text('جارٍ التحميل...'),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  late List<CameraDescription> cameras;
  bool _isInitialized = false;
  String? _savedImagePath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.medium);
    await _controller!.initialize();
    if (!mounted) return;

    setState(() => _isInitialized = true);

    // الالتقاط التلقائي بعد فتح الكاميرا
    await Future.delayed(const Duration(milliseconds: 500));
    _takePicture();
  }

  Future<void> _takePicture() async {
    if (!_controller!.value.isInitialized) return;

    try {
      final image = await _controller!.takePicture();

      final Directory dir = await getApplicationDocumentsDirectory();
      final String newPath = join(
        dir.path,
        'captured_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final File newImage = await File(image.path).copy(newPath);

      setState(() {
        _savedImagePath = newImage.path;
      });

      print("✅ الصورة تم حفظها في: $_savedImagePath");
    } catch (e) {
      print("❌ فشل في التقاط الصورة: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('كاميرا')),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_controller!)),
          const SizedBox(height: 8),
          if (_savedImagePath != null) ...[
            const Text('📸 تم التقاط الصورة:'),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.file(
                File(_savedImagePath!),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
