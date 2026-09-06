import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/offline/local_cache.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/qty.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_qty_stepper.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_unit_chips.dart';
import '../../core/widgets/nf_widgets.dart';
import 'ledger_data.dart';
import 'ledger_pages.dart';

/// Dialogue de revente rapide — retourne true si une vente a été enregistrée.
Future<bool> showQuickProductSellDialog(
  BuildContext context,
  WidgetRef ref,
  SaleProduct product,
) async {
  final t = ref.read(nfStringsProvider);
  final fmt = NumberFormat.decimalPattern('fr');
  var unite = 'u';
  for (final raw in ref.read(localCacheProvider).getList(LocalCacheKeys.stock)) {
    final n = raw['nom']?.toString().trim().toLowerCase() ?? '';
    if (n == product.nom.trim().toLowerCase()) {
      unite = normalizeUnite(raw['unite']?.toString());
      break;
    }
  }
  final step = qtyStepForUnit(unite);
  double qty = roundQty(product.lastQty.clamp(step, 9999));
  final unitCtrl = TextEditingController(text: '${product.unitPriceFcfa}');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        final unit = int.tryParse(unitCtrl.text) ?? product.unitPriceFcfa;
        final total = (qty * unit).round();
        return AlertDialog(
          title: Text(product.nom),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('myProductsHint'),
                style: TextStyle(color: NfTokens.textMute, fontSize: 13),
              ),
              const SizedBox(height: 10),
              NfUnitChips(
                value: unite,
                onChanged: (u) => setDialog(() {
                  unite = u;
                  final s = qtyStepForUnit(u);
                  if (qty < s) qty = s;
                }),
              ),
              const SizedBox(height: 14),
              NfQtyStepper(
                label: t('quantity'),
                unitLabel: unitLabelOf(unite, t),
                step: qtyStepForUnit(unite),
                value: qty,
                onBump: (delta) => setDialog(() {
                  qty = roundQty(
                    (qty + delta).clamp(qtyStepForUnit(unite), 9999),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: unitPriceLabelOf(unite, t),
                  suffixText: 'FCFA',
                ),
                onChanged: (_) => setDialog(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                '${t('totalCollected')} · ${fmt.format(total)} FCFA',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: total > 0 ? () => Navigator.of(ctx).pop(true) : null,
              child: Text(t('confirm')),
            ),
          ],
        );
      },
    ),
  );
  if (confirmed != true) return false;

  final unit = int.tryParse(unitCtrl.text) ?? product.unitPriceFcfa;
  final res = await submitProductSale(
    ref,
    productName: product.nom,
    qty: qty,
    unitPriceFcfa: unit,
    canal: product.canal,
  );
  if (!context.mounted) return res.ok;
  final messenger = ScaffoldMessenger.of(context);
  if (res.ok) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          res.offline ? t('savedOffline') : '${t('sale')} · ${product.nom}',
        ),
      ),
    );
  } else if (res.error != null) {
    messenger.showSnackBar(SnackBar(content: Text(res.error!)));
  }
  return res.ok;
}

String _formatLastSold(String? iso, NfStrings t) {
  if (iso == null || iso.isEmpty) return t('neverSold');
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return t('neverSold');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today) {
    return '${t('today')} · ${DateFormat.Hm('fr').format(dt)}';
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return t('yesterday');
  }
  return DateFormat('dd MMM', 'fr').format(dt);
}

/// Page dédiée — catalogue des produits déjà vendus + revente rapide.
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  List<SaleProduct> products = [];
  String query = '';
  String? busyId;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
      if (ref.read(uxPrefsProvider).voiceAssist) {
        ref.read(voiceServiceProvider).speakKey('myProducts');
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    final list = loadSaleProducts(ref.read(localCacheProvider));
    if (!mounted) return;
    setState(() => products = list);
  }

  List<SaleProduct> get _filtered {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) => p.nom.toLowerCase().contains(q)).toList();
  }

  Future<void> _sell(SaleProduct p) async {
    if (busyId != null) return;
    setState(() => busyId = p.id);
    final ok = await showQuickProductSellDialog(context, ref, p);
    if (!mounted) return;
    setState(() => busyId = null);
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;
    final fmt = NumberFormat.decimalPattern('fr');
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app/ventes'),
        title: Text(t('myProducts')),
        actions: const [NfSpeakButton(labelKey: 'myProducts', alwaysShow: true)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NfTokens.brand,
        foregroundColor: NfTokens.onBrand,
        onPressed: () => context.push('/app/enregistrer'),
        icon: const Icon(Icons.add),
        label: Text(t('recordSale')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.format('productsCount', {'n': '${products.length}'}),
                  style: TextStyle(
                    color: NfTokens.textMute,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t('myProductsHint'),
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                if (products.length > 4) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      hintText: t('searchProduct'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: NfTokens.elevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: NfTokens.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: NfTokens.line),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 48),
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 56,
                        color: NfTokens.textMute,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        query.isEmpty ? t('noProductsYet') : t('noProductMatch'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: NfTokens.textMute,
                          fontSize: 16,
                        ),
                      ),
                      if (query.isEmpty) ...[
                        const SizedBox(height: 20),
                        NfPrimaryButton(
                          label: t('recordSale'),
                          onPressed: () => context.push('/app/enregistrer'),
                        ),
                      ],
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      final busy = busyId == p.id;
                      final initial = p.nom.trim().isNotEmpty
                          ? p.nom.trim()[0].toUpperCase()
                          : '?';
                      return Material(
                        color: NfTokens.elevated,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: busy ? null : () => _sell(p),
                          child: Container(
                            padding: EdgeInsets.all(iconMode ? 16 : 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: NfTokens.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: iconMode ? 52 : 44,
                                      height: iconMode ? 52 : 44,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: NfTokens.brand
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        initial,
                                        style: TextStyle(
                                          color: NfTokens.brandSoft,
                                          fontWeight: FontWeight.w900,
                                          fontSize: iconMode ? 22 : 18,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.nom,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: iconMode ? 20 : 17,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatLastSold(p.lastSoldAt, t),
                                            style: TextStyle(
                                              color: NfTokens.textMute,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      fmt.format(p.unitPriceFcfa),
                                      style: TextStyle(
                                        color: NfTokens.brandSoft,
                                        fontWeight: FontWeight.w900,
                                        fontSize: iconMode ? 22 : 18,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'FCFA / ${unitLabelOf('u', t)}',
                                    style: TextStyle(
                                      color: NfTokens.textMute,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _MetaChip(
                                      icon: Icons.shopping_bag_outlined,
                                      label: t.format(
                                        'timesSold',
                                        {'n': '${p.saleCount}'},
                                      ),
                                    ),
                                    _MetaChip(
                                      icon: Icons.numbers,
                                      label:
                                          '${t('quantity')} · ${formatQty(p.lastQty)}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: iconMode ? 52 : 46,
                                  child: FilledButton.icon(
                                    onPressed: busy ? null : () => _sell(p),
                                    icon: Icon(
                                      busy ? Icons.hourglass_top : Icons.sell_outlined,
                                    ),
                                    label: Text(
                                      busy ? '…' : t('quickSell'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: iconMode ? 17 : 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NfTokens.card2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NfTokens.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: NfTokens.textMute),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: NfTokens.textMute,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
