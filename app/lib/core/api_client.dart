import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import 'network.dart';
import 'session.dart';

/// Thin HTTP client: resolves the current server address and adds the
/// bearer token on every request. 401 responses log the user out.
class ApiClient {
  ApiClient(this._ref) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          o.baseUrl = '${_ref.read(routeProvider).baseUrl}$apiPrefix';
          final tok = _ref.read(tokenProvider);
          if (tok.isNotEmpty) o.headers['Authorization'] = 'Bearer $tok';
          h.next(o);
        },
        onError: (e, h) {
          if (e.response?.statusCode == 401 && _ref.read(tokenProvider).isNotEmpty) {
            _ref.read(sessionProvider.notifier).logout();
          }
          h.next(e);
        },
      ),
    );
  }

  final Ref _ref;
  final _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 30)),
  );

  Future<dynamic> get(String path, {Map<String, dynamic>? query, CancelToken? cancel}) async =>
      (await _dio.get(path, queryParameters: query, cancelToken: cancel)).data;

  Future<dynamic> post(String path, [Object? body]) async => (await _dio.post(path, data: body)).data;

  Future<dynamic> patch(String path, Object body) async => (await _dio.patch(path, data: body)).data;

  Future<dynamic> put(String path, [Object? body]) async => (await _dio.put(path, data: body)).data;

  Future<dynamic> delete(String path) async => (await _dio.delete(path)).data;

  /// Absolute URL for media endpoints (stream, covers).
  String url(String path) => '${_ref.read(routeProvider).baseUrl}$apiPrefix$path';

  Map<String, String> get authHeaders => {'Authorization': 'Bearer ${_ref.read(tokenProvider)}'};
}

final apiProvider = Provider<ApiClient>((ref) => ApiClient(ref));

/// Human-readable message for errors shown in the UI.
String errorMessage(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    return switch (e.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.connectionError => 'Serveur injoignable',
      DioExceptionType.receiveTimeout => 'Le serveur ne répond pas',
      _ => e.message ?? 'Erreur réseau',
    };
  }
  return e.toString();
}
