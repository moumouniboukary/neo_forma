import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/session.dart';
import 'config.dart';

export 'config.dart' show ApiException, resolveApiBase;

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(sessionStorageProvider));
});

class ApiClient {
  ApiClient(this._session) {
    _dio = Dio(
      BaseOptions(
        baseUrl: resolveApiBase(),
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _session.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode ?? 0;
          final path = error.requestOptions.path;
          if (status == 401 &&
              !path.contains('/auth/') &&
              error.requestOptions.extra['retried'] != true) {
            final ok = await _tryRefresh();
            if (ok) {
              final req = error.requestOptions;
              req.extra['retried'] = true;
              final token = await _session.getAccessToken();
              if (token != null) {
                req.headers['Authorization'] = 'Bearer $token';
              }
              try {
                final res = await _dio.fetch(req);
                return handler.resolve(res);
              } catch (e) {
                return handler.next(error);
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final SessionStorage _session;
  late final Dio _dio;
  Future<bool>? _refreshInFlight;

  Future<bool> _tryRefresh() {
    return _refreshInFlight ??= () async {
      try {
        final refresh = await _session.getRefreshToken();
        if (refresh == null) return false;
        final res = await Dio(
          BaseOptions(baseUrl: resolveApiBase()),
        ).post('/auth/refresh', data: {'refreshToken': refresh});
        if (res.statusCode != 200) return false;
        final data = res.data as Map<String, dynamic>;
        final user = StoredUser.fromJson(data['user'] as Map<String, dynamic>);
        await _session.setSession(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String?,
          user: user,
        );
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshInFlight = null;
      }
    }();
  }

  Future<T> get<T>(
    String path, {
    T Function(dynamic data)? parse,
  }) async {
    try {
      final res = await _dio.get(path);
      return parse != null ? parse(res.data) : res.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    try {
      // Corps {} par défaut : Fastify refuse Content-Type JSON sans body.
      final res = await _dio.post(path, data: data ?? const <String, dynamic>{});
      return parse != null ? parse(res.data) : res.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    try {
      final res = await _dio.patch(path, data: data ?? const <String, dynamic>{});
      return parse != null ? parse(res.data) : res.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    try {
      final res = await _dio.put(path, data: data ?? const <String, dynamic>{});
      return parse != null ? parse(res.data) : res.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<T?> delete<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    try {
      final res = await _dio.delete(path, data: data);
      if (parse != null) return parse(res.data);
      return res.data as T?;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.unknown && e.response == null) {
      return ApiException('Hors ligne', status: 0, body: {'offline': true});
    }
    final data = e.response?.data;
    String message = e.message ?? 'Erreur réseau';
    if (data is Map && data['message'] is String) {
      message = data['message'] as String;
    }
    return ApiException(
      message,
      status: e.response?.statusCode ?? 0,
      body: data,
    );
  }
}
