import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredUser {
  StoredUser({
    required this.id,
    required this.phone,
    required this.displayName,
    required this.onboardingCompleted,
    this.language,
    this.statutCompte,
  });

  final String id;
  final String phone;
  final String displayName;
  final bool onboardingCompleted;
  final String? language;
  final String? statutCompte;

  factory StoredUser.fromJson(Map<String, dynamic> json) {
    return StoredUser(
      id: json['id'] as String,
      phone: (json['phone'] ?? json['telephone'] ?? '') as String,
      displayName: (json['displayName'] ?? json['nomAffiche'] ?? '') as String,
      onboardingCompleted: json['onboardingCompleted'] == true ||
          json['onboardingTermine'] == true,
      language: json['language'] as String?,
      statutCompte: json['statutCompte'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'displayName': displayName,
        'onboardingCompleted': onboardingCompleted,
        'language': language,
        'statutCompte': statutCompte,
      };

  StoredUser copyWith({
    String? displayName,
    bool? onboardingCompleted,
    String? language,
    String? statutCompte,
  }) {
    return StoredUser(
      id: id,
      phone: phone,
      displayName: displayName ?? this.displayName,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      language: language ?? this.language,
      statutCompte: statutCompte ?? this.statutCompte,
    );
  }
}

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'neoforma.accessToken';
  static const _refreshKey = 'neoforma.refreshToken';
  static const _userKey = 'neoforma.user';

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<StoredUser?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    return StoredUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setSession({
    required String accessToken,
    required StoredUser user,
    String? refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    if (refreshToken != null) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
  }

  Future<void> setUser(StoredUser user) async {
    final access = await getAccessToken();
    final refresh = await getRefreshToken();
    if (access == null) return;
    await setSession(
      accessToken: access,
      user: user,
      refreshToken: refresh,
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }
}
