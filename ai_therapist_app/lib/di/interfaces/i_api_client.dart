// lib/di/interfaces/i_api_client.dart
import 'dart:async';
import 'dart:typed_data';
import '../../models/tts_config.dart';
abstract class IApiClient {
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParams,
  });
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  });
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  });
  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, String>? headers,
  });
  Future<Map<String, dynamic>> uploadFile(
    String endpoint,
    String fieldName,
    Uint8List fileData,
    String fileName, {
    Map<String, String>? headers,
    Map<String, String>? additionalFields,
  });
  Future<Uint8List> downloadFile(String url);
  void setAuthToken(String token);
  void clearAuthToken();
  String? get authToken;
  String get baseUrl;
  void setBaseUrl(String url);
  void setTimeout(Duration timeout);
  Future<TtsConfigDto?> fetchTtsConfig();
  Future<bool> checkConnection();
  bool get isConnected;
  Stream<String> get errorStream;
  Future<void> initialize();
  void dispose();
}
