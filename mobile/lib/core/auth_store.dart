import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

class AuthStore {
  AuthStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const defaultBaseUrl = 'http://10.0.2.2:8000';
  final FlutterSecureStorage _storage;
  ApiClient? api;

  Future<ApiClient?> restore() async {
    final values = await _storage.readAll();
    final baseUrl = values['base_url'];
    final refreshToken = values['refresh_token'];
    final accessToken = values['access_token'];
    if (baseUrl == null || refreshToken == null) return null;
    try {
      final response = await http.post(
        Uri.parse(
          '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/auth/refresh',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode != 200) {
        await signOut();
        return null;
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      await _save(baseUrl, body);
      return api;
    } catch (_) {
      // Keep the last session so the home screen can expose downloaded books
      // while offline. Network calls may fail, but local manifests remain usable.
      if (accessToken == null) return null;
      api = ApiClient(
        baseUrl: baseUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return api;
    }
  }

  Future<ApiClient> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await http.post(
      Uri.parse('$normalized/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode != 200) {
      var message = '登录失败，请检查账号、密码和服务器地址';
      try {
        message =
            (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['detail']
                ?.toString() ??
            message;
      } catch (_) {}
      throw ApiException(message, statusCode: response.statusCode);
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    await _save(normalized, body);
    return api!;
  }

  Future<void> _save(String baseUrl, Map<String, dynamic> body) async {
    await _storage.write(key: 'base_url', value: baseUrl);
    await _storage.write(
      key: 'access_token',
      value: body['access_token'] as String,
    );
    await _storage.write(
      key: 'refresh_token',
      value: body['refresh_token'] as String,
    );
    api = ApiClient(
      baseUrl: baseUrl,
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
    );
  }

  Future<void> signOut() async {
    api = null;
    await _storage.deleteAll();
  }
}
