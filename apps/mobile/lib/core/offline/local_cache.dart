import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Cache locale offline-first — Hive box `neoforma_local_cache`.
///
/// Stocke la dernière réponse API connue pour chaque écran clé
/// (opérations, clients, dashboard, stock, tontines, notifications, score)
/// afin que l'app reste utilisable hors ligne : on tente l'API en premier,
/// puis on retombe sur le cache en cas d'échec, et on réécrit le cache après
/// chaque récupération réussie.
class LocalCacheKeys {
  static const operations = 'operations';
  static const clients = 'clients';
  static const dashboard = 'dashboard';
  static const stock = 'stock';
  static const tontines = 'tontines';
  static const notifications = 'notifications';
  static const score = 'score';
  static const uxPrefs = 'ux_prefs';
}

class LocalCache {
  static const _boxName = 'neoforma_local_cache';
  late Box<String> _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  List<Map<String, dynamic>> getList(String key) {
    final raw = _box.get(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> putList(String key, List<Map<String, dynamic>> items) async {
    await _box.put(key, jsonEncode(items));
  }

  Map<String, dynamic>? getMap(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> putMap(String key, Map<String, dynamic> value) async {
    await _box.put(key, jsonEncode(value));
  }

  /// Fusionne une liste entrante dans le cache existant par `id`
  /// (utilisé pour merger les pulls incrémentaux opérations/clients).
  Future<void> mergeListById(
    String key,
    List<Map<String, dynamic>> incoming,
  ) async {
    if (incoming.isEmpty) return;
    final existing = getList(key);
    final byId = <String, Map<String, dynamic>>{};
    for (final item in existing) {
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) byId[id] = item;
    }
    for (final item in incoming) {
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) byId[id] = item;
    }
    await putList(key, byId.values.toList());
  }

  Future<void> clear() async {
    await _box.clear();
  }
}

final localCacheProvider = Provider<LocalCache>((ref) {
  throw UnimplementedError('LocalCache must be overridden in main');
});
