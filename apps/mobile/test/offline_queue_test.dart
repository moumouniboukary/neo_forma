import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neoforma/core/offline/queue.dart';

void main() {
  group('QueuedMutation', () {
    test('round-trip toJson / fromJson conserve les données', () {
      final m = QueuedMutation(
        clientMutationId: 'mut-1',
        kind: 'create_operation',
        payload: {'type': 'vente', 'amountFcfa': 2500},
        createdAt: '2026-01-01T00:00:00.000Z',
      );

      final encoded = jsonEncode(m.toJson());
      final decoded =
          QueuedMutation.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded.clientMutationId, 'mut-1');
      expect(decoded.kind, 'create_operation');
      expect(decoded.payload['type'], 'vente');
      expect(decoded.payload['amountFcfa'], 2500);
      expect(decoded.createdAt, '2026-01-01T00:00:00.000Z');
      expect(decoded.status, 'pending');
    });

    test('copyWith marke failed conserve les données', () {
      final m = QueuedMutation(
        clientMutationId: 'mut-2',
        kind: 'create_client',
        payload: {'nom': 'Awa'},
        createdAt: '2026-01-01T00:00:00.000Z',
      );
      final failed = m.copyWith(status: 'failed', failReason: 'validation');
      expect(failed.status, 'failed');
      expect(failed.failReason, 'validation');
      expect(failed.kind, 'create_client');
    });

    test('newId génère des identifiants uniques', () {
      final a = OfflineQueue.newId();
      final b = OfflineQueue.newId();
      expect(a, isNotEmpty);
      expect(a, isNot(equals(b)));
    });
  });
}
