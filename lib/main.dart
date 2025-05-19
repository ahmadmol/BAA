import 'package:flutter/material.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [CameraNavigatorObserver()],
      home: const AuthGate(),
    );
  }
}

class CameraNavigatorObserver extends NavigatorObserver {
  @override
  void didPop(Route route, Route? previousRoute) {
    if (previousRoute?.settings.name == '/camera') {
      final cameraState = route.navigator?.context.findAncestorStateOfType<_CameraScreenState>();
      cameraState?._disposeCamera();
    }
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
        MaterialPageRoute(
          builder: (_) => const CameraScreen(),
          settings: const RouteSettings(name: '/camera'),
        ),
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

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  late List<CameraDescription> cameras;
  bool _isInitialized = false;
  String? _savedImagePath;
  String? _serverResponse;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && !_isInitialized) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      cameras = await availableCameras();
      _controller = CameraController(cameras[0], ResolutionPreset.medium);
      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isInitialized = true);

      await Future.delayed(const Duration(milliseconds: 500));
      await _takePicture();
    } catch (e) {
      print("❌ فشل في تهيئة الكاميرا: $e");
    }
  }

  void _disposeCamera() {
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
      setState(() => _isInitialized = false);
    }
  }

  Future<void> _takePicture() async {
    if (!_isInitialized || _isProcessing || _controller == null || !_controller!.value.isInitialized) return;

    setState(() => _isProcessing = true);

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
        _serverResponse = null;
      });

      print("✅ الصورة تم حفظها في: $_savedImagePath");
      await sendImageToServer(_savedImagePath!);
    } catch (e) {
      print("❌ فشل في التقاط الصورة: $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> sendImageToServer(String imagePath) async {
    final uri = Uri.parse('http://YOUR_PYTHON_SERVER_IP:5000/predict');
    final request = http.MultipartRequest('POST', uri);

    try {
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      final response = await request.send();

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        print('Response from server: $respStr');
        setState(() {
          _serverResponse = respStr;
        });
      } else {
        print('Failed to get response from server: ${response.statusCode}');
        setState(() {
          _serverResponse = 'Failed: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('Error sending image: $e');
      setState(() {
        _serverResponse = 'Error: $e';
      });
    }
  }

  @override
  void dispose() {
    _disposeCamera();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('مساعد المكفوفين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _isProcessing ? null : _takePicture,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller!),
                if (_isProcessing)
                  const CircularProgressIndicator(),
              ],
            ),
          ),
          if (_savedImagePath != null) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.file(
                File(_savedImagePath!),
                width: 200,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (_serverResponse != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _serverResponse!,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _takePicture,
              child: _isProcessing
                  ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('جاري المعالجة...'),
                ],
              )
                  : const Text('التقاط صورة جديدة'),
            ),
          ),
        ],
      ),
    );
  }
}