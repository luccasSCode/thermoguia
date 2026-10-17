import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/local_store.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;

  bool get isOffline => status == null;

  @override
  String toString() => message;
}

/// Cliente HTTP do backend. Converte qualquer falha em [ApiException]
/// com mensagem pronta para exibir.
class ApiClient {
  ApiClient(this._store)
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 50),
          contentType: 'application/json',
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = _store.token;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  final Dio _dio;
  final LocalStore _store;

  /// Chamado quando o servidor recusa a sessão (401).
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get(path, queryParameters: query));
  Future<dynamic> post(String path, [Object? body]) => _wrap(() => _dio.post(path, data: body));
  Future<dynamic> put(String path, [Object? body]) => _wrap(() => _dio.put(path, data: body));
  Future<dynamic> patch(String path, [Object? body]) => _wrap(() => _dio.patch(path, data: body));
  Future<dynamic> delete(String path) => _wrap(() => _dio.delete(path));

  /// Envia bytes crus (ex.: foto de perfil) com o tipo informado.
  Future<dynamic> putBytes(String path, List<int> bytes, String contentType) => _wrap(() => _dio.put(
        path,
        data: Stream.fromIterable([bytes]),
        options: Options(contentType: contentType, headers: {Headers.contentLengthHeader: bytes.length}),
      ));

  Future<List<int>> getBytes(String path) async =>
      (await _wrap(() => _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes)))) as List<int>;

  Future<dynamic> _wrap(Future<Response<dynamic>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) onUnauthorized?.call();
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        throw ApiException(data['error'] as String, status);
      }
      if (status == null) {
        throw ApiException(switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout =>
            'O servidor do ThermoGuia demorou para responder. Tente de novo em instantes.',
          _ => 'Não foi possível falar com o servidor do ThermoGuia. '
              'Confira sua internet ou tente de novo em instantes.',
        });
      }
      throw ApiException('Algo deu errado ($status). Tente novamente.', status);
    }
  }
}
