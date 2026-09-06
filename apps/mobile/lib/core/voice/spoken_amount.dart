import 'dart:math';

import 'package:intl/intl.dart';

/// Extrait un montant entier (FCFA) depuis une phrase STT.
///
/// [lang] : `fr` ou `mr`. En mooré, on interprète d’abord les mots mooré
/// (y compris ce que le STT français a mal orthographié), puis les chiffres,
/// puis le français (mélange fréquent).
int? parseSpokenAmount(
  String? raw, {
  String lang = 'fr',
  Iterable<String> alternates = const [],
}) {
  final seen = <String>{};
  final texts = <String>[];
  void add(String? s) {
    final t = s?.trim() ?? '';
    if (t.isEmpty) return;
    final k = t.toLowerCase();
    if (seen.add(k)) texts.add(t);
  }

  add(raw);
  for (final a in alternates) {
    add(a);
  }
  if (texts.isEmpty) return null;

  for (final t in texts) {
    final n = _parseOne(t, lang);
    if (n != null && n > 0) return n;
  }
  return null;
}

String formatFcfa(int amount) =>
    NumberFormat.decimalPattern('fr').format(amount);

int? _parseOne(String text, String lang) {
  final digits = _parseDigitGroups(text);
  if (lang == 'mr') {
    final mr = _parseMooreWords(text);
    if (mr != null && mr > 0) return mr;
    if (digits != null && digits > 0) return digits;
    final fr = _parseFrenchWords(text);
    if (fr != null && fr > 0) return fr;
    return null;
  }
  if (digits != null && digits >= 10) return digits;
  final fr = _parseFrenchWords(text);
  if (fr != null && fr > 0) return fr;
  final mr = _parseMooreWords(text);
  if (mr != null && mr > 0) return mr;
  if (digits != null && digits > 0) return digits;
  return null;
}

const _frSmall = <String, int>{
  'zero': 0,
  'zéro': 0,
  'un': 1,
  'une': 1,
  'deux': 2,
  'trois': 3,
  'quatre': 4,
  'cinq': 5,
  'six': 6,
  'sept': 7,
  'huit': 8,
  'neuf': 9,
  'dix': 10,
  'onze': 11,
  'douze': 12,
  'treize': 13,
  'quatorze': 14,
  'quinze': 15,
  'seize': 16,
  'vingt': 20,
  'vingts': 20,
  'trente': 30,
  'quarante': 40,
  'cinquante': 50,
  'soixante': 60,
};

int? _parseDigitGroups(String raw) {
  final groups =
      RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)!).toList();
  if (groups.isEmpty) return null;
  if (groups.length == 1) return int.tryParse(groups.first);
  if (groups.skip(1).every((g) => g.length == 3)) {
    return int.tryParse(groups.join());
  }
  groups.sort((a, b) => b.length.compareTo(a.length));
  return int.tryParse(groups.first);
}

List<String> _tokens(String raw) {
  var s = raw.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'[àáâä]'), 'a');
  s = s.replaceAll(RegExp(r'[èéêëẽ]'), 'e');
  s = s.replaceAll(RegExp(r'[ìíîïĩɩ]'), 'i');
  s = s.replaceAll(RegExp(r'[òóôöõɔ]'), 'o');
  s = s.replaceAll(RegExp(r'[ùúûüũʋ]'), 'u');
  s = s.replaceAll('ÿ', 'y');
  s = s.replaceAll('ç', 'c');
  s = s.replaceAll(RegExp(r"['’`]"), ' ');
  s = s.replaceAll(RegExp(r'[-/]'), ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  return s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

int? _parseFrenchWords(String raw) {
  final tokens = _tokens(raw)
      .where(
        (t) =>
            t != 'franc' &&
            t != 'francs' &&
            t != 'fcfa' &&
            t != 'cfa' &&
            t != 'f' &&
            t != 'et' &&
            t != 'de',
      )
      .toList();
  if (tokens.isEmpty) return null;

  var total = 0;
  var current = 0;
  var used = false;

  int i = 0;
  while (i < tokens.length) {
    final t = tokens[i];
    final asInt = int.tryParse(t);
    if (asInt != null) {
      current += asInt;
      used = true;
      i++;
      continue;
    }
    if (t == 'quatre' &&
        i + 1 < tokens.length &&
        (tokens[i + 1] == 'vingt' || tokens[i + 1] == 'vingts')) {
      var v = 80;
      i += 2;
      if (i < tokens.length &&
          _frSmall.containsKey(tokens[i]) &&
          _frSmall[tokens[i]]! <= 19) {
        v += _frSmall[tokens[i]]!;
        i++;
      }
      current += v;
      used = true;
      continue;
    }
    if (t == 'soixante' &&
        i + 1 < tokens.length &&
        _frSmall.containsKey(tokens[i + 1]) &&
        _frSmall[tokens[i + 1]]! >= 10 &&
        _frSmall[tokens[i + 1]]! <= 19) {
      current += 60 + _frSmall[tokens[i + 1]]!;
      used = true;
      i += 2;
      continue;
    }
    if (t == 'cent' || t == 'cents') {
      current = (current == 0 ? 1 : current) * 100;
      used = true;
      i++;
      continue;
    }
    if (t == 'mille' || t == 'milles' || t == 'mil') {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
      used = true;
      i++;
      continue;
    }
    if (t == 'million' || t == 'millions') {
      total += (current == 0 ? 1 : current) * 1000000;
      current = 0;
      used = true;
      i++;
      continue;
    }
    final small = _frSmall[t];
    if (small != null) {
      current += small;
      used = true;
      i++;
      continue;
    }
    i++;
  }
  if (!used) return null;
  return total + current;
}

/// Variantes STT français → mot mooré canonique (puis valeur).
const _mrSmall = <String, int>{
  'yembre': 1,
  'yembere': 1,
  'yemre': 1,
  'yem': 1,
  'yambre': 1,
  'yiibu': 2,
  'yibu': 2,
  'yiibou': 2,
  'yibou': 2,
  'iibu': 2,
  'hibou': 2,
  'taabo': 3,
  'tabo': 3,
  'taanbo': 3,
  'tambo': 3,
  'naase': 4,
  'nase': 4,
  'nasse': 4,
  'naas': 4,
  'gnasse': 4,
  'nu': 5,
  'nou': 5,
  'nous': 5,
  'yoobe': 6,
  'yobe': 6,
  'yoob': 6,
  'yopoe': 7,
  'yopwe': 7,
  'yopoue': 7,
  'yopoi': 7,
  'nii': 8,
  'nid': 8,
  'we': 9,
  'wen': 9,
  'oue': 9,
  'ouais': 9,
  'ouin': 9,
  'piiga': 10,
  'piga': 10,
  'pigaa': 10,
  'pika': 10,
  'piqua': 10,
};

const _mrTens = <String, int>{
  'pisiyi': 20,
  'pisyi': 20,
  'pisi': 20,
  'pistaabo': 30,
  'pistabo': 30,
  'pisnaase': 40,
  'pisnase': 40,
  'pisnu': 50,
  'pisnou': 50,
  'pisyoobe': 60,
  'pisyobe': 60,
  'pisyopoe': 70,
  'pisnii': 80,
  'piswe': 90,
};

const _mrSkip = {
  'la',
  'a',
  'an',
  'ne',
  'n',
  'ligdi',
  'frank',
  'francs',
  'franc',
  'fcfa',
  'cfa',
  'il',
  'y',
};

const _mrCanonForFuzzy = [
  'yembre',
  'yiibu',
  'taabo',
  'naase',
  'yoobe',
  'yopoe',
  'piiga',
  'piga',
  'tusa',
  'tusri',
  'toussa',
  'koabga',
  'koabgo',
  'pisiyi',
  'pistaabo',
  'pisnaase',
];

/// Phrases que le STT français produit souvent pour du mooré parlé.
const _mrPhraseRewrite = <(String, String)>[
  ('tout ca nous', 'tusa nu'),
  ('tout sa nous', 'tusa nu'),
  ('tous a nous', 'tusa nu'),
  ('tous sa nous', 'tusa nu'),
  ('tout ca nu', 'tusa nu'),
  ('tout ca', 'tusa'),
  ('tout sa', 'tusa'),
  ('tous a', 'tusa'),
  ('tous sa', 'tusa'),
  ('tout ça', 'tusa'),
  ('yen bref', 'yembre'),
  ('yaim bref', 'yembre'),
  ('yam bre', 'yembre'),
  ('il y a bout', 'yiibu'),
  ('t as beau', 'taabo'),
  ('tas beau', 'taabo'),
];

int? _mrValue(String t) => _mrSmall[t] ?? _mrTens[t];

String _fold(String t) {
  var s = t;
  s = s.replaceAll('ou', 'u');
  s = s.replaceAll('oi', 'oa');
  s = s.replaceAll('qu', 'k');
  s = s.replaceAll('c', 'k');
  s = s.replaceAll('k', 'g');
  s = s.replaceAll(RegExp(r'(.)\1+'), r'$1');
  return s;
}

int _lev(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    var diag = prev[0];
    prev[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final tmp = prev[j];
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      prev[j] = min(min(prev[j] + 1, prev[j - 1] + 1), diag + cost);
      diag = tmp;
    }
  }
  return prev[b.length];
}

String _mapMrToken(String t) {
  if (_mrSkip.contains(t)) return t;
  if (_mrSmall.containsKey(t) ||
      _mrTens.containsKey(t) ||
      t == 'tusri' ||
      t == 'tusa' ||
      t == 'toussa' ||
      t == 'tousri' ||
      t == 'tousa' ||
      t == 'tous' ||
      t == 'koabga' ||
      t == 'koabgo' ||
      t == 'koaga' ||
      t == 'koab' ||
      t == 'kouabga' ||
      t == 'pis' ||
      t == 'pisi' ||
      t == 'pisn') {
    return t;
  }
  if (t.length < 4) return t;
  final folded = _fold(t);
  String? best;
  var bestD = 99;
  for (final canon in _mrCanonForFuzzy) {
    final d = _lev(folded, _fold(canon));
    final maxD = t.length >= 6 ? 2 : 1;
    if (d <= maxD && d < bestD) {
      bestD = d;
      best = canon;
    }
  }
  return best ?? t;
}

List<String> _rewriteMrPhrases(List<String> tokens) {
  var s = ' ${tokens.join(' ')} ';
  for (final pair in _mrPhraseRewrite) {
    s = s.replaceAll(' ${pair.$1} ', ' ${pair.$2} ');
  }
  return s.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

int? _parseMooreWords(String raw) {
  final tokens = _rewriteMrPhrases(_tokens(raw)).map(_mapMrToken).toList();
  final kept = tokens.where((t) => !_mrSkip.contains(t)).toList();
  if (kept.isEmpty) return null;

  var total = 0;
  var current = 0;
  var used = false;

  int i = 0;
  while (i < kept.length) {
    final t = kept[i];
    final asInt = int.tryParse(t);
    if (asInt != null) {
      current += asInt;
      used = true;
      i++;
      continue;
    }

    if (t == 'pis' || t == 'pisi' || t == 'pisn') {
      final next = i + 1 < kept.length ? _mrSmall[kept[i + 1]] : null;
      if (next != null && next >= 1 && next <= 9) {
        current += next * 10;
        used = true;
        i += 2;
        continue;
      }
      current += 20;
      used = true;
      i++;
      continue;
    }

    if (t == 'koabga' ||
        t == 'koabgo' ||
        t == 'koaga' ||
        t == 'koab' ||
        t == 'kouabga') {
      final next = i + 1 < kept.length ? _mrSmall[kept[i + 1]] : null;
      if (next != null && next >= 1 && next <= 9) {
        total += next * 100;
        used = true;
        i += 2;
        continue;
      }
      if (current > 0) {
        total += current * 100;
        current = 0;
      } else {
        total += 100;
      }
      used = true;
      i++;
      continue;
    }

    if (t == 'tusri' ||
        t == 'tusa' ||
        t == 'toussa' ||
        t == 'tousri' ||
        t == 'tousa' ||
        t == 'tous') {
      final next = i + 1 < kept.length
          ? (_mrValue(kept[i + 1]) ?? _mrSmall[kept[i + 1]])
          : null;
      if (next != null && next >= 1 && next < 1000) {
        total += next * 1000;
        used = true;
        i += 2;
        continue;
      }
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
      used = true;
      i++;
      continue;
    }

    final v = _mrValue(t);
    if (v != null) {
      current += v;
      used = true;
      i++;
      continue;
    }
    i++;
  }
  if (!used) return null;
  return total + current;
}
