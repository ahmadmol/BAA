// services/processing_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';

class ProcessingService {
  final FlutterTts _tts = FlutterTts();
  late Directory resultsDir;

  Future<void> initialize() async {
    await _tts.setLanguage("ar-SA");
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    List<dynamic> voices = await _tts.getVoices;
    for (var voice in voices) {
      if ((voice['locale'] ?? '').toLowerCase().contains('ar') &&
          (voice['name'] ?? '').toLowerCase().contains('google')) {
        await _tts.setVoice({'name': voice['name'], 'locale': voice['locale']});
        break;
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    resultsDir = Directory('${appDir.path}/results');
    if (!await resultsDir.exists()) {
      await resultsDir.create(recursive: true);
    }
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> saveImage(Uint8List imageBytes) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${resultsDir.path}/processed_$timestamp.jpg');
    await file.writeAsBytes(imageBytes);
  }
}
