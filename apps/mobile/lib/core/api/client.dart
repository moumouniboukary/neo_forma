import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/session.dart';
import 'config.dart';

export 'config.dart' show ApiException, resolveApiBase;

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage();
});

final apiClientProvider = Provider<ApiClient>(
  (ref) {
    return ApiClient(ref.watch(sessionStorageProvider));
  },
  dependencies: [sessionStorageProvider],
);

class ApiClient {
  ApiClient(this._session) {
    _dio = Dio(
      BaseOptions(
        baseUrl: resolveApiBase(),
        // Render free peut mettre ~30–60 s à se réveiller.
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 60),
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
                // Afficher l'erreur du retry (ex. 400 quantité), pas le 401 d'origine.
                if (e is DioException) return handler.next(e);
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
    return _withColdStartRetry(() async {
      final res = await _dio.get(path);
      return parse != null ? parse(res.data) : res.data as T;
    });
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    return _withColdStartRetry(() async {
      // Corps {} par défaut : Fastify refuse Content-Type JSON sans body.
      final res = await _dio.post(path, data: data ?? const <String, dynamic>{});
      return parse != null ? parse(res.data) : res.data as T;
    });
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    return _withColdStartRetry(() async {
      final res =
          await _dio.patch(path, data: data ?? const <String, dynamic>{});
      return parse != null ? parse(res.data) : res.data as T;
    });
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    return _withColdStartRetry(() async {
      final res = await _dio.put(path, data: data ?? const <String, dynamic>{});
      return parse != null ? parse(res.data) : res.data as T;
    });
  }

  Future<T?> delete<T>(
    String path, {
    Object? data,
    T Function(dynamic data)? parse,
  }) async {
    return _withColdStartRetry(() async {
      final res = await _dio.delete(path, data: data);
      if (parse != null) return parse(res.data);
      return res.data as T?;
    });
  }

  /// Render free s'endort : 2 relances espacées avant d'abandonner.
  Future<T> _withColdStartRetry<T>(Future<T> Function() call) async {
    DioException? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await call();
      } on DioException catch (e) {
        last = e;
        final retryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.type == DioExceptionType.unknown && e.response == null);
        if (!retryable || attempt == 2) break;
        await Future<void>.delayed(Duration(seconds: 2 + attempt * 3));
      }
    }
    throw _mapError(last!);
  }

  ApiException _mapError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException(
        'Serveur lent ou en démarrage — réessayez dans 1 minute (Wi‑Fi ne suffit pas si l’API dort).',
        status: 0,
        body: {'offline': true, 'reason': 'timeout'},
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        (e.type == DioExceptionType.unknown && e.response == null)) {
      return ApiException(
        'Serveur injoignable — vérifiez Internet, puis réessayez.',
        status: 0,
        body: {'offline': true, 'reason': 'unreachable'},
      );
    }
    final data = e.response?.data;
    String message = e.message ?? 'Erreur réseau';
    if (data is Map && data['message'] is String) {
      message = data['message'] as String;
      final details = data['details'];
      if (details is Map) {
        final fieldErrors = details['fieldErrors'];
        if (fieldErrors is Map && fieldErrors.isNotEmpty) {
          final parts = <String>[];
          for (final entry in fieldErrors.entries) {
            final v = entry.value;
            if (v is List && v.isNotEmpty) {
              parts.add('${entry.key}: ${v.first}');
            }
          }
          if (parts.isNotEmpty && !message.contains('(')) {
            message = '$message (${parts.join(', ')})';
          }
        }
      }
    }
    return ApiException(
      message,
      status: e.response?.statusCode ?? 0,
      body: data,
    );
  }
}
