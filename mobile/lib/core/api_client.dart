import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.accessToken,
    required this.refreshToken,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;
  String accessToken;
  String refreshToken;

  Uri uri(String path) =>
      Uri.parse('$baseUrl${path.startsWith('/') ? path : '/$path'}');

  String absoluteUrl(String path) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('file://')) {
      return path;
    }
    return uri(path).toString();
  }

  Map<String, String> get authHeaders => {
    'Authorization': 'Bearer $accessToken',
  };

  Map<String, String> _jsonHeaders({String? pin}) {
    final headers = {...authHeaders, 'Content-Type': 'application/json'};
    if (pin != null) {
      headers['X-Parent-Pin'] = pin;
    }
    return headers;
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        body = response.body;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map ? body['detail'] : body;
      throw ApiException(
        detail?.toString() ?? '服务器请求失败',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Future<List<BookSummary>> listBooks() async {
    final response = await http.get(uri('/api/v1/books'), headers: authHeaders);
    final body = _decode(response) as List;
    return body
        .map(
          (item) =>
              BookSummary.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<int> createBook(String title, String pin) async {
    final response = await http.post(
      uri('/api/v1/books'),
      headers: _jsonHeaders(pin: pin),
      body: jsonEncode({'title': title}),
    );
    return (_decode(response) as Map)['id'] as int;
  }

  Future<Map<String, dynamic>> uploadPage({
    required int bookId,
    required File file,
    required String uploadKey,
    required int orderIndex,
    required bool isCover,
    required String pin,
  }) async {
    final request =
        http.MultipartRequest('POST', uri('/api/v1/books/$bookId/pages'))
          ..headers.addAll({...authHeaders, 'X-Parent-Pin': pin})
          ..fields.addAll({
            'upload_key': uploadKey,
            'order_index': '$orderIndex',
            'is_cover': '$isCover',
          })
          ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<void> reorderPages(int bookId, List<int> pageIds, String pin) async {
    final response = await http.put(
      uri('/api/v1/books/$bookId/pages/reorder'),
      headers: _jsonHeaders(pin: pin),
      body: jsonEncode({'page_ids': pageIds}),
    );
    _decode(response);
  }

  Future<void> deletePage(int bookId, int pageId, String pin) async {
    final response = await http.delete(
      uri('/api/v1/books/$bookId/pages/$pageId'),
      headers: {...authHeaders, 'X-Parent-Pin': pin},
    );
    _decode(response);
  }

  Future<int> analyzeBook(int bookId, String idempotencyKey, String pin) async {
    final response = await http.post(
      uri('/api/v1/books/$bookId/analyze'),
      headers: _jsonHeaders(pin: pin),
      body: jsonEncode({'idempotency_key': idempotencyKey}),
    );
    return (_decode(response) as Map)['id'] as int;
  }

  Future<Map<String, dynamic>> getJob(int jobId) async {
    final response = await http.get(
      uri('/api/v1/jobs/$jobId'),
      headers: authHeaders,
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<BookDetail> getBook(int bookId) async {
    final response = await http.get(
      uri('/api/v1/books/$bookId'),
      headers: authHeaders,
    );
    return BookDetail.fromJson(
      Map<String, dynamic>.from(_decode(response) as Map),
    );
  }

  Future<void> saveReview(BookDetail book, String pin) async {
    final pageChanges = <String, dynamic>{};
    for (final page in book.pages.where((item) => !item.isCover)) {
      pageChanges['${page.id}'] = {
        'order_index': page.orderIndex,
        'original_text': page.originalText,
        'zh_text': page.zhText,
        'en_text': page.enText,
        'explanation': page.explanation,
        'question': page.question,
      };
    }
    final response = await http.put(
      uri('/api/v1/books/${book.id}/review'),
      headers: _jsonHeaders(pin: pin),
      body: jsonEncode({
        'title': book.title,
        'summary': book.summary,
        'completeness_status': book.completenessStatus,
        'pages': pageChanges,
      }),
    );
    _decode(response);
  }

  Future<int> confirmBook(int bookId, String idempotencyKey, String pin) async {
    final response = await http.post(
      uri('/api/v1/books/$bookId/confirm'),
      headers: _jsonHeaders(pin: pin),
      body: jsonEncode({'idempotency_key': idempotencyKey}),
    );
    return (_decode(response) as Map)['id'] as int;
  }

  Future<OfflineManifestData> getManifest(int bookId) async {
    final response = await http.get(
      uri('/api/v1/books/$bookId/manifest'),
      headers: authHeaders,
    );
    return OfflineManifestData.fromJson(
      Map<String, dynamic>.from(_decode(response) as Map),
    );
  }

  Future<List<int>> getBytes(String path) async {
    final response = await http.get(
      Uri.parse(absoluteUrl(path)),
      headers: authHeaders,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
    return response.bodyBytes;
  }

  Future<void> deleteBook(int bookId, String pin) async {
    final response = await http.delete(
      uri('/api/v1/books/$bookId'),
      headers: {...authHeaders, 'X-Parent-Pin': pin},
    );
    _decode(response);
  }
}
