class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.body});

  final String message;
  final int status;
  final dynamic body;

  bool get isOffline => status == 0;
  bool get isServerError => status >= 500;

  @override
  String toString() => message;
}

/// API_BASE via --dart-define=API_BASE=http://10.0.2.2:3001
String resolveApiBase() {
  const fromEnv = String.fromEnvironment('API_BASE');
  if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');
  // Émulateur Android → machine hôte
  return 'http://10.0.2.2:3001';
}
