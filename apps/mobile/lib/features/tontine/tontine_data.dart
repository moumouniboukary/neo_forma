import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/offline/local_cache.dart';

class TontineCotisation {
  const TontineCotisation({
    required this.id,
    required this.montantFcfa,
    required this.datePaiement,
  });

  final String id;
  final int montantFcfa;
  final String datePaiement;

  factory TontineCotisation.fromMap(Map<String, dynamic> m) =>
      TontineCotisation(
        id: m['id']?.toString() ?? '',
        montantFcfa: (m['montantFcfa'] as num?)?.toInt() ?? 0,
        datePaiement: m['datePaiement']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'montantFcfa': montantFcfa,
    'datePaiement': datePaiement,
  };
}

class TontineInfo {
  const TontineInfo({
    required this.id,
    required this.nom,
    required this.cotisationFcfa,
    required this.frequence,
    required this.membres,
    required this.actif,
    this.cotisations = const [],
  });

  final String id;
  final String nom;
  final int cotisationFcfa;
  final String frequence;
  final int membres;
  final bool actif;
  final List<TontineCotisation> cotisations;

  factory TontineInfo.fromMap(Map<String, dynamic> m) => TontineInfo(
    id: m['id']?.toString() ?? '',
    nom: m['nom']?.toString() ?? 'Tontine',
    cotisationFcfa: (m['cotisationFcfa'] as num?)?.toInt() ?? 0,
    frequence: m['frequence']?.toString() ?? 'mensuel',
    membres: (m['membres'] as num?)?.toInt() ?? 1,
    actif: m['actif'] != false,
    cotisations: ((m['cotisations'] as List?) ?? [])
        .map((e) => TontineCotisation.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'nom': nom,
    'cotisationFcfa': cotisationFcfa,
    'frequence': frequence,
    'membres': membres,
    'actif': actif,
    'cotisations': cotisations.map((c) => c.toMap()).toList(),
  };
}

final tontineRevisionProvider = StateProvider<int>((ref) => 0);

final tontinesProvider = FutureProvider.autoDispose<List<TontineInfo>>((
  ref,
) async {
  ref.watch(tontineRevisionProvider);
  final api = ref.watch(apiClientProvider);
  final cache = ref.watch(localCacheProvider);
  try {
    final res = await api.get<Map<String, dynamic>>(
      '/tontine',
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    final items = ((res['items'] as List?) ?? [])
        .map((e) => TontineInfo.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    await cache.putList(
      LocalCacheKeys.tontines,
      items.map((e) => e.toMap()).toList(),
    );
    return items;
  } catch (_) {
    return cache.getList(LocalCacheKeys.tontines).map(TontineInfo.fromMap).toList();
  }
});

class TontineRepository {
  TontineRepository(this._api);
  final ApiClient _api;

  Future<TontineInfo> create({
    required String nom,
    required int cotisationFcfa,
    String frequence = 'mensuel',
    int membres = 1,
  }) async {
    final m = await _api.post<Map<String, dynamic>>(
      '/tontine',
      data: {
        'nom': nom,
        'cotisationFcfa': cotisationFcfa,
        'frequence': frequence,
        'membres': membres,
      },
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    return TontineInfo.fromMap(m);
  }

  Future<void> addCotisation(String tontineId, int montantFcfa) {
    return _api.post(
      '/tontine/$tontineId/cotisations',
      data: {'montantFcfa': montantFcfa},
    );
  }
}

final tontineRepositoryProvider = Provider<TontineRepository>(
  (ref) => TontineRepository(ref.watch(apiClientProvider)),
);
