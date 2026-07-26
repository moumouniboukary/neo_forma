import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/offline/local_cache.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.titre,
    required this.corps,
    required this.lu,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String titre;
  final String corps;
  final bool lu;
  final String createdAt;

  factory NotificationItem.fromMap(Map<String, dynamic> m) => NotificationItem(
    id: m['id']?.toString() ?? '',
    type: m['type']?.toString() ?? '',
    titre: m['titre']?.toString() ?? 'NeoForma',
    corps: m['corps']?.toString() ?? '',
    lu: m['lu'] == true,
    createdAt: m['createdAt']?.toString() ?? '',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'titre': titre,
    'corps': corps,
    'lu': lu,
    'createdAt': createdAt,
  };

  NotificationItem copyWith({bool? lu}) => NotificationItem(
    id: id,
    type: type,
    titre: titre,
    corps: corps,
    lu: lu ?? this.lu,
    createdAt: createdAt,
  );
}

final notificationsRevisionProvider = StateProvider<int>((ref) => 0);

/// Liste des notifications — API en premier, cache local si hors ligne.
final notificationsProvider =
    FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
      ref.watch(notificationsRevisionProvider);
      final api = ref.watch(apiClientProvider);
      final cache = ref.watch(localCacheProvider);
      try {
        final res = await api.get<Map<String, dynamic>>(
          '/notifications',
          parse: (d) => Map<String, dynamic>.from(d as Map),
        );
        final items = ((res['items'] as List?) ?? [])
            .map((e) => NotificationItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        await cache.putList(
          LocalCacheKeys.notifications,
          items.map((e) => e.toMap()).toList(),
        );
        return items;
      } catch (_) {
        return cache
            .getList(LocalCacheKeys.notifications)
            .map(NotificationItem.fromMap)
            .toList();
      }
    });

final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final async = ref.watch(notificationsProvider);
  return async.maybeWhen(
    data: (items) => items.where((n) => !n.lu).length,
    orElse: () => 0,
  );
});

class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  Future<void> markRead(String id) => _api.post('/notifications/$id/read');
  Future<void> markAllRead() => _api.post('/notifications/read-all');
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

/// Types de notifications déclenchant une alerte système locale.
const _pushWorthyTypes = {'credit_decision', 'creance_retard'};

/// Sondage périodique — à appeler après chaque [SyncService.flush] ou à
/// l'initialisation de l'écran principal. Émet une notification locale pour
/// tout nouvel élément non lu de type crédit/retard, sans jamais doublonner.
class NotificationsPoller {
  NotificationsPoller(this._ref);
  final Ref _ref;
  final Set<String> _seen = {};

  Future<void> pollAndNotify() async {
    try {
      final api = _ref.read(apiClientProvider);
      final res = await api.get<Map<String, dynamic>>(
        '/notifications?unreadOnly=1&limit=20',
        parse: (d) => Map<String, dynamic>.from(d as Map),
      );
      final items = (res['items'] as List?) ?? [];
      var isFirstRun = _seen.isEmpty;
      for (final raw in items) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty || _seen.contains(id)) continue;
        _seen.add(id);
        final type = m['type']?.toString() ?? '';
        // On ne notifie pas rétroactivement au tout premier sondage
        // (éviterait un déluge de notifs pour l'historique existant).
        if (isFirstRun || !_pushWorthyTypes.contains(type)) continue;
        await NotificationService.instance.show(
          id: id.hashCode,
          title: m['titre']?.toString() ?? 'NeoForma',
          body: m['corps']?.toString() ?? '',
        );
      }
      _ref.read(notificationsRevisionProvider.notifier).state++;
    } catch (_) {
      // silencieux — pas de réseau
    }
  }
}

final notificationsPollerProvider = Provider<NotificationsPoller>(
  (ref) => NotificationsPoller(ref),
);
