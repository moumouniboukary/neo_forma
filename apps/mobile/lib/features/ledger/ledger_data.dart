import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client.dart';
import '../../core/offline/local_cache.dart';
import '../../core/utils/parse.dart';
import '../../core/utils/qty.dart';

/// Client informel (débiteur) rattaché à une créance.
class ClientInfo {
  const ClientInfo({required this.id, required this.nom, this.telephone});

  final String id;
  final String nom;
  final String? telephone;

  factory ClientInfo.fromMap(Map<String, dynamic> m) => ClientInfo(
        id: m['id'].toString(),
        nom: m['nom']?.toString() ?? 'Client',
        telephone: m['telephone']?.toString(),
      );
}

/// Révision globale des données du cahier.
/// Incrémentée à chaque changement (création, règlement, synchronisation).
/// Les écrans qui l'observent se rechargent automatiquement.
final ledgerRevisionProvider = StateProvider<int>((ref) => 0);

/// Liste des clients — API puis cache local hors ligne.
final clientsProvider = FutureProvider.autoDispose<List<ClientInfo>>(
  (ref) async {
    ref.watch(ledgerRevisionProvider);
    final api = ref.watch(apiClientProvider);
    final cache = ref.watch(localCacheProvider);
    try {
      final list = await api.get<List>('/clients', parse: (d) => d as List);
      final mapped = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await cache.putList(LocalCacheKeys.clients, mapped);
      return mapped.map(ClientInfo.fromMap).toList();
    } catch (_) {
      return cache
          .getList(LocalCacheKeys.clients)
          .map(ClientInfo.fromMap)
          .toList();
    }
  },
  dependencies: [ledgerRevisionProvider, apiClientProvider, localCacheProvider],
);

class ClientsRepository {
  ClientsRepository(this._api);

  final ApiClient _api;

  Future<ClientInfo> create({required String nom, String? telephone}) async {
    final m = await _api.post<Map<String, dynamic>>(
      '/clients',
      data: {
        'nom': nom,
        if (telephone != null && telephone.trim().isNotEmpty)
          'telephone': telephone.trim(),
      },
      parse: (d) => Map<String, dynamic>.from(d as Map),
    );
    return ClientInfo.fromMap(m);
  }

  Future<void> delete(String id) => _api.delete('/clients/$id');
}

final clientsRepositoryProvider = Provider<ClientsRepository>(
  (ref) => ClientsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Produit déjà vendu — pour revente rapide (nom + dernier prix unitaire).
class SaleProduct {
  const SaleProduct({
    required this.nom,
    required this.unitPriceFcfa,
    this.lastQty = 1,
    this.canal = 'especes',
    this.saleCount = 1,
    this.lastSoldAt,
  });

  final String nom;
  final int unitPriceFcfa;
  final double lastQty;
  final String canal;
  final int saleCount;
  final String? lastSoldAt;

  String get id => nom.trim().toLowerCase();

  Map<String, dynamic> toMap() => {
        'id': id,
        'nom': nom,
        'unitPriceFcfa': unitPriceFcfa,
        'lastQty': lastQty,
        'canal': canal,
        'saleCount': saleCount,
        if (lastSoldAt != null) 'lastSoldAt': lastSoldAt,
      };

  factory SaleProduct.fromMap(Map<String, dynamic> m) => SaleProduct(
        nom: m['nom']?.toString() ?? 'Produit',
        unitPriceFcfa: asFcfaInt(m['unitPriceFcfa']),
        lastQty: roundQty(asQty(m['lastQty'], fallback: 1).clamp(0.001, 999999)),
        canal: m['canal']?.toString() ?? 'especes',
        saleCount: asFcfaInt(m['saleCount'], fallback: 1),
        lastSoldAt: m['lastSoldAt']?.toString(),
      );

  SaleProduct copyWith({
    int? unitPriceFcfa,
    double? lastQty,
    String? canal,
    int? saleCount,
    String? lastSoldAt,
  }) =>
      SaleProduct(
        nom: nom,
        unitPriceFcfa: unitPriceFcfa ?? this.unitPriceFcfa,
        lastQty: lastQty ?? this.lastQty,
        canal: canal ?? this.canal,
        saleCount: saleCount ?? this.saleCount,
        lastSoldAt: lastSoldAt ?? this.lastSoldAt,
      );
}

/// Extrait nom / qté / prix depuis un libellé « Riz · 3 × 500 » ou « Bœuf · 1,5 × 3500 ».
({String? nom, double? qty, int? unitPrice}) parseSaleLabel(String? label) {
  if (label == null || label.trim().isEmpty) {
    return (nom: null, qty: null, unitPrice: null);
  }
  final m = RegExp(
    r'^(.+?)\s·\s([\d]+(?:[.,]\d+)?)\s×\s(\d+)$',
  ).firstMatch(label.trim());
  if (m != null) {
    return (
      nom: m.group(1)?.trim(),
      qty: parseQty(m.group(2)),
      unitPrice: int.tryParse(m.group(3) ?? ''),
    );
  }
  final m2 = RegExp(r'^(.+?)\s×\s([\d]+(?:[.,]\d+)?)$').firstMatch(label.trim());
  if (m2 != null) {
    return (
      nom: m2.group(1)?.trim(),
      qty: parseQty(m2.group(2)),
      unitPrice: null,
    );
  }
  if (label.trim().toLowerCase() == 'vente') {
    return (nom: null, qty: null, unitPrice: null);
  }
  return (nom: label.trim(), qty: null, unitPrice: null);
}

List<SaleProduct> loadSaleProducts(LocalCache cache) {
  final list = cache
      .getList(LocalCacheKeys.saleProducts)
      .map(SaleProduct.fromMap)
      .where((p) => p.nom.trim().isNotEmpty && p.unitPriceFcfa > 0)
      .toList();
  list.sort((a, b) {
    final at = a.lastSoldAt ?? '';
    final bt = b.lastSoldAt ?? '';
    return bt.compareTo(at);
  });
  return list;
}

Future<void> rememberSaleProduct(
  LocalCache cache, {
  required String nom,
  required int unitPriceFcfa,
  required double qty,
  String canal = 'especes',
  String? soldAt,
}) async {
  final clean = nom.trim();
  if (clean.isEmpty || unitPriceFcfa <= 0) return;
  final id = clean.toLowerCase();
  final existing = cache.getList(LocalCacheKeys.saleProducts);
  final byId = <String, Map<String, dynamic>>{};
  for (final item in existing) {
    final k = item['id']?.toString() ?? item['nom']?.toString().toLowerCase();
    if (k != null && k.isNotEmpty) byId[k] = item;
  }
  final prev = byId[id];
  final prevCount = asFcfaInt(prev?['saleCount']);
  byId[id] = SaleProduct(
    nom: clean,
    unitPriceFcfa: unitPriceFcfa,
    lastQty: roundQty(qty.clamp(0.001, 999999)),
    canal: canal,
    saleCount: prevCount + 1,
    lastSoldAt: soldAt ?? DateTime.now().toUtc().toIso8601String(),
  ).toMap();
  await cache.putList(LocalCacheKeys.saleProducts, byId.values.toList());
}

/// Reconstruit / enrichit le catalogue à partir des ventes connues.
Future<void> hydrateSaleProductsFromOps(
  LocalCache cache,
  List<Map<String, dynamic>> ventes,
) async {
  final existing = cache.getList(LocalCacheKeys.saleProducts);
  final byId = <String, Map<String, dynamic>>{};
  for (final item in existing) {
    final k = item['id']?.toString() ?? item['nom']?.toString().toLowerCase();
    if (k != null && k.isNotEmpty) byId[k] = item;
  }

  for (final op in ventes) {
    final parsed = parseSaleLabel(op['label']?.toString());
    final nom = (op['productName']?.toString().trim().isNotEmpty == true)
        ? op['productName'].toString().trim()
        : parsed.nom;
    if (nom == null || nom.isEmpty) continue;
    final qty = asQty(
      op['quantity'] ?? op['quantiteStock'] ?? parsed.qty,
      fallback: 1,
    ).clamp(0.001, 999999);
    final amount = asFcfaInt(op['amountFcfa']);
    final unit = parsed.unitPrice ??
        (qty > 0 && amount > 0 ? (amount / qty).round() : 0);
    if (unit <= 0) continue;
    final id = nom.toLowerCase();
    if (byId.containsKey(id)) continue;
    byId[id] = SaleProduct(
      nom: nom,
      unitPriceFcfa: unit,
      lastQty: roundQty(qty.clamp(0.001, 999999)),
      canal: op['canal']?.toString() ?? 'especes',
      saleCount: 1,
      lastSoldAt:
          op['dateOperation']?.toString() ?? op['createdAt']?.toString(),
    ).toMap();
  }

  await cache.putList(LocalCacheKeys.saleProducts, byId.values.toList());
}
