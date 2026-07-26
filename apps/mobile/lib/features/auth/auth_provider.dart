import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/storage/session.dart';

enum OtpPurpose { login, register, reset }

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
    _bootstrap();
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
      data: {'phone': phone, 'purpose': purpose.name},
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    return (
      expiresIn: data['expiresIn'] as int? ?? 300,
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
      data: {'phone': phone, 'code': code, 'purpose': purpose.name},
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
      data: {'phone': phone, 'pin': pin, 'otpToken': otpToken},
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
        'phone': phone,
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
    final data = await _api.get<Map<String, dynamic>>(
      '/me',
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    final user = StoredUser.fromJson(data);
    await _session.setUser(user);
    state = state.copyWith(user: user);
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

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(apiClientProvider),
    ref.watch(sessionStorageProvider),
  );
});
