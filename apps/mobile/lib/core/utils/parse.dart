/// Parse robuste des nombres venant de l'API / cache JSON
/// (`int`, `double`, `String`, espaces).
int asFcfaInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(
        value.toString().replaceAll(RegExp(r'[\s\u00a0]'), ''),
      ) ??
      fallback;
}

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

bool isUuid(String? value) {
  final s = value?.trim() ?? '';
  return s.isNotEmpty && _uuidRe.hasMatch(s);
}

/// Comme [asFcfaInt], mais `null` si la clé est absente / vide.
int? asFcfaIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is String && value.trim().isEmpty) return null;
  return asFcfaInt(value);
}

/// Parse robuste en `double` (critères score, ratios, etc.).
double asNumDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(
        value
            .toString()
            .replaceAll(RegExp(r'[\s\u00a0]'), '')
            .replaceAll(',', '.'),
      ) ??
      fallback;
}
