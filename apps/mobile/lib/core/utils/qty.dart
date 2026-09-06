import 'parse.dart';

double roundQty(num n) => (n * 1000).round() / 1000;

double asQty(dynamic value, {double fallback = 0}) =>
    roundQty(asNumDouble(value, fallback: fallback));

double parseQty(String? raw, {double fallback = 0}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  return asQty(raw, fallback: fallback);
}

/// JSON : entier si la qté est ronde (évite 20.0 rejeté par l’ancienne API).
num jsonQty(num n) {
  final v = roundQty(n);
  if (v == v.roundToDouble()) return v.round();
  return v;
}

/// Affichage FR : `1,5` / entier sans virgule.
String formatQty(num n) {
  final v = roundQty(n);
  if (v == v.roundToDouble()) return '${v.round()}';
  var s = v.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s.replaceAll('.', ',');
}

double qtyStepForUnit(String unite) =>
    (unite == 'kg' || unite == 'g' || unite == 'l') ? 0.1 : 1;

String normalizeUnite(String? raw) {
  final x = (raw ?? 'u').trim().toLowerCase();
  if (x == 'kg' || x == 'kilo' || x == 'kilos') return 'kg';
  if (x == 'g' || x == 'gr' || x == 'gramme' || x == 'grammes') return 'g';
  if (x == 'l' || x == 'L' || x == 'litre' || x == 'litres') return 'l';
  return 'u';
}

/// Ajoute un chiffre ou une virgule (max 3 décimales).
String appendQtyDigit(String current, String d) {
  if (d == ',' || d == '.') {
    if (current.contains(',') || current.contains('.')) return current;
    return current.isEmpty ? '0,' : '$current,';
  }
  final sep = current.contains(',')
      ? ','
      : current.contains('.')
          ? '.'
          : null;
  if (sep != null) {
    final frac = current.split(sep).last;
    if (frac.length >= 3) return current;
  }
  final digits = current.replaceAll(RegExp(r'[,.]'), '');
  if (digits.length >= 8) return current;
  if (current == '0') return d;
  return '$current$d';
}
