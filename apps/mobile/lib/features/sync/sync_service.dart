import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/offline/local_cache.dart';
import '../../core/offline/queue.dart';
import '../../core/riverpod_safe.dart';
import '../ledger/ledger_data.dart';
import '../stock/stock_data.dart';

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
    scheduleProviderWrite(() {
      _ref.read(syncPendingProvider.notifier).state = _queue.count;
    });
  }

  /// Précharge les écrans clés pour qu'ils restent utilisables hors ligne.
  Future<void> warmCaches() async {
    Future<void> warmList(String path, String cacheKey) async {
      try {
        final list = await _api.get<List>(path, parse: (d) => d as List);
        final mapped =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _cache.putList(cacheKey, mapped);
      } catch (_) {
        if (!_cache.hasKey(cacheKey)) {
          await _cache.putList(cacheKey, const []);
        }
      }
    }

    Future<void> warmMap(String path, String cacheKey) async {
      try {
        final map = await _api.get<Map<String, dynamic>>(
          path,
          parse: (d) => Map<String, dynamic>.from(d as Map),
        );
        await _cache.putMap(cacheKey, map);
      } catch (_) {
        /* conserve le cache existant */
      }
    }

    Future<void> warmStock() async {
      try {
        final res = await _api.get<Map<String, dynamic>>(
          '/stock/articles',
          parse: (d) => Map<String, dynamic>.from(d as Map),
        );
        final items = ((res['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        await _cache.putList(LocalCacheKeys.stock, items);
      } catch (_) {
        if (!_cache.hasKey(LocalCacheKeys.stock)) {
          await _cache.putList(LocalCacheKeys.stock, const []);
        }
      }
    }

    await Future.wait([
      warmList('/operations', LocalCacheKeys.operations),
      warmList('/clients', LocalCacheKeys.clients),
      warmStock(),
      warmList('/tontines', LocalCacheKeys.tontines),
      warmList('/notifications', LocalCacheKeys.notifications),
      warmMap('/dashboard', LocalCacheKeys.dashboard),
      warmMap('/score', LocalCacheKeys.score),
      warmMap('/me', LocalCacheKeys.profile),
    ]);
  }

  void _notifyChanged({bool stock = false}) {
    scheduleProviderWrite(() {
      _ref.read(ledgerRevisionProvider.notifier).state++;
      if (stock) {
        _ref.read(stockRevisionProvider.notifier).state++;
      }
    });
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
      var stockChanged = false;
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
          if (accepted.isNotEmpty) {
            changed = true;
            if (mutations.any(
              (m) => accepted.contains(m.clientMutationId) && m.kind == 'upsert_stock',
            )) {
              stockChanged = true;
            }
          }

          // Rejets : on conserve localement (status failed), on ne rejoue plus.
          if (rejected.isNotEmpty) {
            for (final raw in rejected) {
              final map = Map<String, dynamic>.from(raw as Map);
              final id = map['clientMutationId']?.toString();
              final reason = map['reason']?.toString() ?? 'rejeté';
              if (id != null) await _queue.markFailed(id, reason);
            }
            final reason = (rejected.first as Map)['reason']?.toString();
            scheduleProviderWrite(() {
              _ref.read(syncErrorProvider.notifier).state = reason;
            });
          } else {
            scheduleProviderWrite(() {
              _ref.read(syncErrorProvider.notifier).state = null;
            });
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
          final stock = (pull['stock'] as List?) ?? [];
          final ids = ops.map((e) => (e as Map)['id'].toString()).toSet();
          final firstPull = _seenOps.isEmpty && ids.isNotEmpty;
          final hasNew = ids.any((id) => !_seenOps.contains(id));
          _seenOps.addAll(ids);
          if (firstPull ||
              hasNew ||
              clients.isNotEmpty ||
              stock.isNotEmpty) {
            changed = true;
          }
          if (stock.isNotEmpty) stockChanged = true;

          await _cache.mergeListById(
            LocalCacheKeys.operations,
            ops.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
          await _cache.mergeListById(
            LocalCacheKeys.clients,
            clients.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
          await _cache.mergeListById(
            LocalCacheKeys.stock,
            stock.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
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
        if (changed) _notifyChanged(stock: stockChanged);
        // Après un flush réussi (réseau OK), rafraîchir les caches lecture.
        try {
          await warmCaches();
        } catch (_) {}
      }
    } finally {
      _flushing = false;
    }
  }
}

final syncServiceProvider = Provider<SyncService>(
  (ref) {
    return SyncService(
      ref.watch(apiClientProvider),
      ref.watch(offlineQueueProvider),
      ref.watch(localCacheProvider),
      ref,
    );
  },
  dependencies: [apiClientProvider, offlineQueueProvider, localCacheProvider],
);
