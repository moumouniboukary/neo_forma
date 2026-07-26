import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/offline/local_cache.dart';
import '../../core/offline/queue.dart';
import '../ledger/ledger_data.dart';

final offlineQueueProvider = Provider<OfflineQueue>((ref) {
  throw UnimplementedError('OfflineQueue must be overridden in main');
});

final syncPendingProvider = StateProvider<int>((ref) => 0);
final syncErrorProvider = StateProvider<String?>((ref) => null);

class SyncService {
  SyncService(this._api, this._queue, this._cache, this._ref);

  final ApiClient _api;
  final OfflineQueue _queue;
  final LocalCache _cache;
  final Ref _ref;

  /// Ids d'opérations déjà vues côté serveur — pour ne notifier que sur du neuf.
  final Set<String> _seenOps = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _flushing = false;

  Future<void> refreshCount() async {
    _ref.read(syncPendingProvider.notifier).state = _queue.count;
  }

  void _notifyChanged() {
    _ref.read(ledgerRevisionProvider.notifier).state++;
  }

  /// Écoute les changements de connectivité pour relancer [flush]
  /// automatiquement dès le retour du réseau. Idempotent.
  void startAutoSync() {
    if (_connectivitySub != null) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = !results.contains(ConnectivityResult.none);
      if (online) flush();
    });
  }

  void stopAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final online = !connectivity.contains(ConnectivityResult.none);
      if (!online) {
        await refreshCount();
        return;
      }

      var changed = false;
      final mutations = _queue.list(pendingOnly: true);
      try {
        if (mutations.isNotEmpty) {
          final res = await _api.post<Map<String, dynamic>>(
            '/sync/push',
            data: {
              'mutations': mutations
                  .map(
                    (m) => {
                      'clientMutationId': m.clientMutationId,
                      'kind': m.kind,
                      'payload': m.payload,
                      'createdAt': m.createdAt,
                    },
                  )
                  .toList(),
            },
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
          final accepted =
              (res['accepted'] as List?)?.map((e) => e.toString()).toList() ??
              [];
          final rejected = (res['rejected'] as List?) ?? [];
          await _queue.clearAccepted(accepted);
          if (accepted.isNotEmpty) changed = true;

          // Rejets : on conserve localement (status failed), on ne rejoue plus.
          if (rejected.isNotEmpty) {
            for (final raw in rejected) {
              final map = Map<String, dynamic>.from(raw as Map);
              final id = map['clientMutationId']?.toString();
              final reason = map['reason']?.toString() ?? 'rejeté';
              if (id != null) await _queue.markFailed(id, reason);
            }
            _ref.read(syncErrorProvider.notifier).state =
                (rejected.first as Map)['reason']?.toString();
          } else {
            _ref.read(syncErrorProvider.notifier).state = null;
          }
        }

        // Pull incrémental avec curseur persistant.
        var since =
            _queue.lastPullSince ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String();
        var hasMore = true;
        var pages = 0;
        while (hasMore && pages < 10) {
          pages += 1;
          final pull = await _api.get<Map<String, dynamic>>(
            '/sync/pull?since=${Uri.encodeComponent(since)}&limit=100',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
          final ops = (pull['operations'] as List?) ?? [];
          final clients = (pull['clients'] as List?) ?? [];
          final ids = ops.map((e) => (e as Map)['id'].toString()).toSet();
          final firstPull = _seenOps.isEmpty && ids.isNotEmpty;
          final hasNew = ids.any((id) => !_seenOps.contains(id));
          _seenOps.addAll(ids);
          if (firstPull || hasNew || clients.isNotEmpty) changed = true;

          await _cache.mergeListById(
            LocalCacheKeys.operations,
            ops.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
          await _cache.mergeListById(
            LocalCacheKeys.clients,
            clients.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );

          final next = pull['nextSince']?.toString();
          if (next != null && next.isNotEmpty) {
            since = next;
            await _queue.setLastPullSince(next);
          }
          hasMore = pull['hasMore'] == true;
        }
      } catch (_) {
        // keep queue
      } finally {
        await refreshCount();
        if (changed) _notifyChanged();
      }
    } finally {
      _flushing = false;
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(apiClientProvider),
    ref.watch(offlineQueueProvider),
    ref.watch(localCacheProvider),
    ref,
  );
});
