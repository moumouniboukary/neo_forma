import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/storage/session.dart';
import '../../core/utils/parse.dart';

enum OtpPurpose { login, register, reset }

/// Normalise un numéro Burkina vers `+226XXXXXXXX` (8 chiffres locaux).
String normalizeBfPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('226') && digits.length >= 11) {
    return '+226${digits.substring(3, 11)}';
  }
  if (digits.length >= 8) {
    final local =
        digits.length == 8 ? digits : digits.substring(digits.length - 8);
    return '+226$local';
  }
  return raw.trim();
}

class AuthState {
  const AuthState({this.user, this.token, this.ready = false});

  final StoredUser? user;
  final String? token;
  final bool ready;

  bool get isAuthenticated => token != null && user != null;
  bool get needsOnboarding =>
      isAuthenticated && !(user?.onboardingCompleted ?? false);

  AuthState copyWith({
    StoredUser? user,
    String? token,
    bool? ready,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      token: token ?? this.token,
      ready: ready ?? this.ready,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api, this._session) : super(const AuthState()) {
    // Différé : évite de muter auth pendant le 1er build qui watch le provider.
    Future.microtask(_bootstrap);
  }

  final ApiClient _api;
  final SessionStorage _session;

  Future<void> _bootstrap() async {
    final token = await _session.getAccessToken();
    final user = await _session.getUser();
    state = AuthState(token: token, user: user, ready: true);
  }

  Future<({int expiresIn, String? devCode})> requestOtp(
    String phone,
    OtpPurpose purpose,
  ) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/otp/request',
      data: {'phone': normalizeBfPhone(phone), 'purpose': purpose.name},
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    return (
      expiresIn: asFcfaInt(data['expiresIn'], fallback: 300),
      devCode: data['devCode'] as String?,
    );
  }

  Future<String> verifyOtp(
    String phone,
    String code,
    OtpPurpose purpose,
  ) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      data: {
        'phone': normalizeBfPhone(phone),
        'code': code,
        'purpose': purpose.name,
      },
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    return data['otpToken'] as String;
  }

  Future<StoredUser> login({
    required String phone,
    required String pin,
    required String otpToken,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'phone': normalizeBfPhone(phone),
        'pin': pin,
        'otpToken': otpToken,
      },
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    final user = StoredUser.fromJson(data['user'] as Map<String, dynamic>);
    await _session.setSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String?,
      user: user,
    );
    state = AuthState(
      token: data['accessToken'] as String,
      user: user,
      ready: true,
    );
    return user;
  }

  /// Reprise de session déjà stockée (sans OTP) — utile hors ligne.
  Future<bool> resumeLocalSession() async {
    final token = await _session.getAccessToken();
    final user = await _session.getUser();
    if (token == null || user == null) return false;
    state = AuthState(token: token, user: user, ready: true);
    return true;
  }

  Future<void> register({
    required String phone,
    required String pin,
    required String otpToken,
    required String displayName,
    String language = 'fr',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'phone': normalizeBfPhone(phone),
        'pin': pin,
        'otpToken': otpToken,
        'displayName': displayName,
        'language': language,
      },
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    final user = StoredUser.fromJson(data['user'] as Map<String, dynamic>);
    await _session.setSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String?,
      user: user,
    );
    state = AuthState(
      token: data['accessToken'] as String,
      user: user,
      ready: true,
    );
  }

  Future<void> refreshMe() async {
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/me',
        parse: (d) => Map<String, dynamic>.from(d as Map),
      );
      final user = StoredUser.fromJson(data);
      await _session.setUser(user);
      state = state.copyWith(user: user);
    } on ApiException catch (e) {
      // Session locale conservée hors ligne.
      if (e.isOffline || e.isServerError) return;
      rethrow;
    }
  }

  void setUser(StoredUser user) {
    state = state.copyWith(user: user);
    _session.setUser(user);
  }

  Future<void> logout() async {
    final refresh = await _session.getRefreshToken();
    try {
      await _api.post('/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {}
    await _session.clear();
    state = const AuthState(ready: true);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) {
    return AuthNotifier(
      ref.watch(apiClientProvider),
      ref.watch(sessionStorageProvider),
    );
  },
  dependencies: [apiClientProvider, sessionStorageProvider],
);
