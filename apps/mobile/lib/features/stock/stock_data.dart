import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/offline/local_cache.dart';
import '../../core/utils/parse.dart';
import '../../core/utils/qty.dart';

class ArticleStock {
  const ArticleStock({
    required this.id,
    required this.nom,
    required this.unite,
    required this.quantite,
    this.prixUnitaireFcfa,
  });

  final String id;
  final String nom;
  final String unite;
  final double quantite;
  final int? prixUnitaireFcfa;

  factory ArticleStock.fromMap(Map<String, dynamic> m) => ArticleStock(
    id: m['id']?.toString() ?? '',
    nom: m['nom']?.toString() ?? '',
    unite: m['unite']?.toString() ?? 'u',
    quantite: asQty(m['quantite']),
    prixUnitaireFcfa: asFcfaIntOrNull(m['prixUnitaireFcfa']),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'nom': nom,
    'unite': unite,
    'quantite': quantite,
    if (prixUnitaireFcfa != null) 'prixUnitaireFcfa': prixUnitaireFcfa,
  };
}

final stockRevisionProvider = StateProvider<int>((ref) => 0);

/// Articles en stock — API en premier, cache local si hors ligne/erreur.
final stockArticlesProvider = FutureProvider.autoDispose<List<ArticleStock>>(
  (ref) async {
    ref.watch(stockRevisionProvider);
    final api = ref.watch(apiClientProvider);
    final cache = ref.watch(localCacheProvider);
    try {
      final res = await api.get<Map<String, dynamic>>(
        '/stock/articles',
        parse: (d) => Map<String, dynamic>.from(d as Map),
      );
      final items = ((res['items'] as List?) ?? [])
          .map((e) => ArticleStock.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      await cache.putList(
        LocalCacheKeys.stock,
        items.map((e) => e.toMap()).toList(),
      );
      return items;
    } catch (_) {
      return cache.getList(LocalCacheKeys.stock).map(ArticleStock.fromMap).toList();
    }
  },
  dependencies: [stockRevisionProvider, apiClientProvider, localCacheProvider],
);

class StockRepository {
  StockRepository(this._api);
  final ApiClient _api;

  Future<ArticleStock> create({
    required String nom,
    String? unite,
    double? quantite,
    int? prixUnitaireFcfa,
  }) async {
    final m = await _api.post<Map<String, dynamic>>(
      '/stock/articles',
      data: {
        'nom': nom,
        if (unite != null) 'unite': unite,
        if (quantite != null) 'quantite': jsonQty(quantite),
        if (prixUnitaireFcfa != null) 'prixUnitaireFcfa': prixUnitaireFcfa,
      },
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    return ArticleStock.fromMap(m);
  }
}

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);
