import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class QueuedMutation {
  QueuedMutation({
    required this.clientMutationId,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.status = 'pending',
    this.failReason,
  });

  final String clientMutationId;
  final String kind;
  final Map<String, dynamic> payload;
  final String createdAt;

  /// pending | failed — les failed ne sont plus rejouées automatiquement.
  final String status;
  final String? failReason;

  Map<String, dynamic> toJson() => {
        'clientMutationId': clientMutationId,
        'kind': kind,
        'payload': payload,
        'createdAt': createdAt,
        'status': status,
        if (failReason != null) 'failReason': failReason,
      };

  factory QueuedMutation.fromJson(Map<String, dynamic> json) {
    return QueuedMutation(
      clientMutationId: json['clientMutationId'] as String,
      kind: json['kind'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: json['createdAt'] as String,
      status: json['status'] as String? ?? 'pending',
      failReason: json['failReason'] as String?,
    );
  }

  QueuedMutation copyWith({String? status, String? failReason}) {
    return QueuedMutation(
      clientMutationId: clientMutationId,
      kind: kind,
      payload: payload,
      createdAt: createdAt,
      status: status ?? this.status,
      failReason: failReason ?? this.failReason,
    );
  }
}

class OfflineQueue {
  static const _boxName = 'neoforma_offline_queue';
  static const _metaBox = 'neoforma_sync_meta';
  late Box<String> _box;
  late Box<String> _meta;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    _meta = await Hive.openBox<String>(_metaBox);
  }

  List<QueuedMutation> list({bool pendingOnly = false}) {
    final all = _box.values
        .map((e) => QueuedMutation.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    if (pendingOnly) {
      return all.where((m) => m.status == 'pending').toList();
    }
    return all;
  }

  int get count => list(pendingOnly: true).length;

  Future<void> enqueue(QueuedMutation mutation) async {
    await _box.put(mutation.clientMutationId, jsonEncode(mutation.toJson()));
  }

  Future<void> clearAccepted(List<String> ids) async {
    for (final id in ids) {
      await _box.delete(id);
    }
  }

  Future<void> markFailed(String id, String reason) async {
    final raw = _box.get(id);
    if (raw == null) return;
    final m = QueuedMutation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    await _box.put(
      id,
      jsonEncode(m.copyWith(status: 'failed', failReason: reason).toJson()),
    );
  }

  String? get lastPullSince => _meta.get('lastPullSince');

  Future<void> setLastPullSince(String iso) async {
    await _meta.put('lastPullSince', iso);
  }

  Future<void> clearMeta() async {
    await _meta.clear();
  }

  static String newId() => const Uuid().v4();
}
