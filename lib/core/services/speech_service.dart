import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class SpeechService {
  static final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  static final AudioPlayer _player = AudioPlayer();
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  static bool _recorderReady = false;
  static bool _isRecording = false;
  static String? _activeRecordingPath;

  static Future<bool> init() async {
    if (_recorderReady) return true;
    try {
      await _recorder.openRecorder();
      _recorderReady = true;
      return true;
    } catch (error) {
      debugPrint('Piki recorder init error: $error');
      return false;
    }
  }

  static Future<bool> requestPermissions() async {
    // permission_handler does not support Windows — mic access is controlled
    // by the OS via the manifest capability declaration and Privacy settings.
    if (Platform.isWindows) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  static Future<bool> startRecording() async {
    if (_isRecording) return true;
    final ready = await init();
    if (!ready) return false;

    final hasPermission = await requestPermissions();
    if (!hasPermission) return false;

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}${Platform.pathSeparator}piki_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _player.stop();
      await _recorder.startRecorder(toFile: path, codec: Codec.aacMP4);
      _activeRecordingPath = path;
      _isRecording = true;
      return true;
    } catch (error) {
      debugPrint('Piki recorder start error: $error');
      _activeRecordingPath = null;
      _isRecording = false;
      return false;
    }
  }

  static Future<String> stopAndTranscribe() async {
    final path = await stopRecording();
    if (path == null || path.isEmpty) {
      throw Exception('No audio was recorded.');
    }
    return transcribeFile(path);
  }

  static Future<String?> stopRecording() async {
    if (!_isRecording) return _activeRecordingPath;
    try {
      final stoppedPath = await _recorder.stopRecorder();
      return stoppedPath ?? _activeRecordingPath;
    } finally {
      _isRecording = false;
    }
  }

  static Future<String> transcribeFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Recorded audio file was not found.');
    }
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured.');
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final bytes = await file.readAsBytes();
    final response = await _dio.post<Map<String, dynamic>>(
      _buildUri(backendUrl, 'ai/transcribe').toString(),
      options: Options(headers: _authHeaders(license)),
      data: {
        'deviceId': deviceId,
        'branchId': DatabaseService.currentBranchId,
        'filename': file.uri.pathSegments.isEmpty
            ? 'piki.m4a'
            : file.uri.pathSegments.last,
        'mimeType': 'audio/mp4',
        'audioBase64': base64Encode(bytes),
      },
    );

    final body = response.data ?? const <String, dynamic>{};
    if (body['ok'] != true) {
      throw Exception(body['error'] as String? ?? 'Transcription failed.');
    }
    return (body['text'] as String? ?? '').trim();
  }

  static Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) return;

    try {
      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final license = await _ensureAccess(backendUrl, deviceId);
      final response = await _dio.post<Map<String, dynamic>>(
        _buildUri(backendUrl, 'ai/tts').toString(),
        options: Options(headers: _authHeaders(license)),
        data: {
          'deviceId': deviceId,
          'branchId': DatabaseService.currentBranchId,
          'text': trimmed,
        },
      );

      final body = response.data ?? const <String, dynamic>{};
      if (body['ok'] != true) return;
      final audioBase64 = body['audioBase64'] as String?;
      if (audioBase64 == null || audioBase64.isEmpty) return;

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}${Platform.pathSeparator}piki_reply_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File(path);
      await file.writeAsBytes(base64Decode(audioBase64), flush: true);
      await _player.stop();
      await _player.setFilePath(path);
      await _player.play();
    } catch (error) {
      debugPrint('Piki TTS playback error: $error');
    }
  }

  static Future<void> stopListening() async {
    await stopRecording();
  }

  static Future<void> stopPlayback() async {
    await _player.stop();
  }

  static bool get isListening => _isRecording;

  static Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }
    if (_recorderReady) {
      await _recorder.closeRecorder();
      _recorderReady = false;
    }
    await _player.dispose();
  }

  static Future<LicenseSnapshot> _ensureAccess(
    String backendUrl,
    String deviceId,
  ) async {
    final snapshot = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    if (!snapshot.hasBinding || snapshot.accessToken == null) {
      throw Exception('Cloud subscription not activated.');
    }
    if (!snapshot.allowsFeature('agent')) {
      throw Exception(
        'Your current subscription plan does not include Piki AI.',
      );
    }
    return snapshot;
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $accessToken'};
  }

  static Uri _buildUri(
    String backendUrl,
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    return Uri.parse(
      '$backendUrl/$path',
    ).replace(queryParameters: queryParameters);
  }
}
