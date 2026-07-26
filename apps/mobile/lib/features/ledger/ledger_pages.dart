import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/offline/local_cache.dart';
import '../../core/offline/queue.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_numeric_keypad.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../../core/voice/voice_service.dart';
import '../sync/sync_service.dart';
import 'ledger_data.dart';

class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  String type = 'vente';
  String canal = 'especes';
  String natureStock = 'entree';
  DateTime dueDate = DateTime.now().add(const Duration(days: 7));
  final amountCtrl = TextEditingController(text: '2500');
  final clientCtrl = TextEditingController();
  final productCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  String? selectedClientId;
  bool loading = false;
  bool done = false;
  bool savedOffline = false;
  bool listening = false;
  String? error;

  @override
  void dispose() {
    amountCtrl.dispose();
    clientCtrl.dispose();
    productCtrl.dispose();
    qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _dictateAmount() async {
    setState(() => listening = true);
    try {
      final text = await ref.read(voiceServiceProvider).listenOnce();
      if (text == null || text.isEmpty) return;
      final digits = text.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        setState(() => amountCtrl.text = digits);
      }
    } finally {
      if (mounted) setState(() => listening = false);
    }
  }

  /// Dialogue de création d'un nouveau client → sélectionné automatiquement.
  Future<void> _createClient() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final created = await showDialog<ClientInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final nom = nameCtrl.text.trim();
              if (nom.isEmpty) return;
              try {
                final client = await ref
                    .read(clientsRepositoryProvider)
                    .create(nom: nom, telephone: phoneCtrl.text);
                if (ctx.mounted) Navigator.of(ctx).pop(client);
              } on ApiException catch (e) {
                if (e.isOffline || e.isServerError) {
                  final mutationId = OfflineQueue.newId();
                  final createdAt = DateTime.now().toUtc().toIso8601String();
                  await ref.read(offlineQueueProvider).enqueue(
                        QueuedMutation(
                          clientMutationId: mutationId,
                          kind: 'create_client',
                          payload: {
                            'nom': nom,
                            if (phoneCtrl.text.trim().isNotEmpty)
                              'telephone': phoneCtrl.text.trim(),
                          },
                          createdAt: createdAt,
                        ),
                      );
                  await ref.read(syncServiceProvider).refreshCount();
                  // Hors ligne : on utilise le nom libre jusqu'à la sync.
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(
                      ClientInfo(id: '', nom: nom, telephone: phoneCtrl.text.trim()),
                    );
                  }
                } else if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                }
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (created != null) {
      if (created.id.isNotEmpty) {
        ref.read(ledgerRevisionProvider.notifier).state++;
        setState(() {
          selectedClientId = created.id;
          clientCtrl.text = created.nom;
        });
      } else {
        // Client créé hors ligne — créance via clientName.
        setState(() {
          selectedClientId = null;
          clientCtrl.text = created.nom;
        });
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    final amount = int.tryParse(amountCtrl.text.replaceAll(RegExp(r'\s'), '')) ?? 0;
    final mutationId = OfflineQueue.newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'type': type,
      'amountFcfa': amount,
      if (type == 'vente') 'label': 'Vente',
      if (type == 'stock') ...{
        'label': productCtrl.text.trim().isEmpty
            ? 'Stock'
            : productCtrl.text.trim(),
        'natureStock': natureStock,
        'productName': productCtrl.text.trim().isEmpty
            ? 'Article'
            : productCtrl.text.trim(),
        'quantiteStock':
            int.tryParse(qtyCtrl.text.replaceAll(RegExp(r'\s'), '')) ?? 1,
      },
      if (type == 'depense') 'label': 'Dépense',
      if (type == 'creance') ...{
        if (selectedClientId != null)
          'clientId': selectedClientId
        else
          'clientName':
              clientCtrl.text.trim().isEmpty ? 'Client' : clientCtrl.text.trim(),
        'dueAt': dueDate.toUtc().toIso8601String(),
      },
      if (type == 'vente' || type == 'depense') 'canal': canal,
      'clientMutationId': mutationId,
      'createdAt': createdAt,
    };

    try {
      await ref.read(apiClientProvider).post('/operations', data: payload);
      // Notifie les autres écrans (accueil, cahier, créances) de se recharger.
      ref.read(ledgerRevisionProvider.notifier).state++;
      setState(() {
        savedOffline = false;
        done = true;
      });
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        await ref.read(offlineQueueProvider).enqueue(
              QueuedMutation(
                clientMutationId: mutationId,
                kind: 'create_operation',
                payload: payload,
                createdAt: createdAt,
              ),
            );
        await ref.read(syncServiceProvider).refreshCount();
        setState(() {
          savedOffline = true;
          done = true;
        });
      } else {
        setState(() => error = e.message);
      }
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Scaffold(
        appBar: AppBar(
          leading: nfBackButton(context, fallbackLocation: '/app'),
          title: const Text('Enregistré'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.check_circle, size: 72, color: NfTokens.ok),
              const SizedBox(height: 12),
              Text(
                savedOffline
                    ? 'Enregistré hors ligne — synchronisation au retour du réseau'
                    : 'Synchronisé',
                style: TextStyle(color: NfTokens.textMute),
              ),
              const Spacer(),
              NfPrimaryButton(label: 'Accueil', onPressed: () => context.go('/app')),
              TextButton(
                onPressed: () => setState(() {
                  done = false;
                  amountCtrl.clear();
                }),
                child: const Text('Nouvelle opération'),
              ),
            ],
          ),
        ),
      );
    }

    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('record')),
        actions: [
          NfSpeakButton(
            text: '${t('record')}. ${t(type == 'vente' ? 'sale' : type == 'stock' ? 'stock' : type == 'creance' ? 'receivable' : 'expense')}. ${t('amount')}.',
            alwaysShow: true,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NfSegmented(
            value: type,
            onChanged: (v) => setState(() => type = v),
            options: [
              ('vente', t('sale')),
              ('stock', t('stock')),
              ('creance', t('receivable')),
              ('depense', t('expense')),
            ],
          ),
          if (iconMode) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TypeIcon(
                  icon: Icons.point_of_sale,
                  selected: type == 'vente',
                  onTap: () => setState(() => type = 'vente'),
                  label: t('sale'),
                ),
                _TypeIcon(
                  icon: Icons.inventory_2_outlined,
                  selected: type == 'stock',
                  onTap: () => setState(() => type = 'stock'),
                  label: t('stock'),
                ),
                _TypeIcon(
                  icon: Icons.handshake_outlined,
                  selected: type == 'creance',
                  onTap: () => setState(() => type = 'creance'),
                  label: t('receivable'),
                ),
                _TypeIcon(
                  icon: Icons.money_off_outlined,
                  selected: type == 'depense',
                  onTap: () => setState(() => type = 'depense'),
                  label: t('expense'),
                ),
              ],
            ),
          ],
          if (type == 'creance') ...[
            const SizedBox(height: 16),
            _ClientField(
              selectedClientId: selectedClientId,
              fallbackCtrl: clientCtrl,
              label: t('client'),
              onSelected: (id) => setState(() => selectedClientId = id),
              onCreate: _createClient,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('dueDate')),
              subtitle: Text(
                DateFormat.yMMMd('fr').format(dueDate),
                style: TextStyle(color: NfTokens.textMute),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: dueDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (picked != null) setState(() => dueDate = picked);
              },
            ),
          ],
          if (type == 'stock') ...[
            const SizedBox(height: 16),
            NfSegmented(
              value: natureStock,
              onChanged: (v) => setState(() => natureStock = v),
              options: [
                ('entree', t('stockIn')),
                ('sortie', t('stockOut')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: productCtrl,
              decoration: InputDecoration(labelText: t('articleName')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: t('quantity')),
            ),
          ],
          if (type == 'vente' || type == 'depense') ...[
            const SizedBox(height: 16),
            Text('Canal', style: TextStyle(color: NfTokens.textMute)),
            const SizedBox(height: 8),
            NfSegmented(
              value: canal,
              onChanged: (v) => setState(() => canal = v),
              options: const [
                ('especes', 'Espèces'),
                ('mobile_money', 'Mobile Money'),
              ],
            ),
          ],
          const SizedBox(height: 16),
          NfKeypadAmountField(
            controller: amountCtrl,
            label: t('amount'),
            trailing: IconButton(
              tooltip: 'Dicter le montant',
              onPressed: listening ? null : _dictateAmount,
              icon: Icon(
                listening ? Icons.mic : Icons.mic_none,
                color: listening ? NfTokens.brand : NfTokens.textMute,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: NfTokens.danger)),
          ],
          const SizedBox(height: 20),
          NfPrimaryButton(
            label: t('confirm'),
            loading: loading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// Sélecteur de client pour une créance : liste déroulante des clients
/// existants + option « Nouveau client ». Repli sur un champ texte libre
/// si l'API est injoignable (mode hors-ligne).
class _ClientField extends ConsumerWidget {
  const _ClientField({
    required this.selectedClientId,
    required this.fallbackCtrl,
    required this.label,
    required this.onSelected,
    required this.onCreate,
  });

  final String? selectedClientId;
  final TextEditingController fallbackCtrl;
  final String label;
  final ValueChanged<String?> onSelected;
  final Future<void> Function() onCreate;

  static const _newValue = '__new__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);
    return clientsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => TextField(
        controller: fallbackCtrl,
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Hors ligne — saisie libre',
        ),
      ),
      data: (clients) {
        final valid = clients.any((c) => c.id == selectedClientId)
            ? selectedClientId
            : null;
        return DropdownButtonFormField<String>(
          initialValue: valid,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          hint: const Text('Choisir un client'),
          items: [
            ...clients.map(
              (c) => DropdownMenuItem(value: c.id, child: Text(c.nom)),
            ),
            const DropdownMenuItem(
              value: _newValue,
              child: Row(
                children: [
                  Icon(Icons.add, size: 18),
                  SizedBox(width: 8),
                  Text('Nouveau client'),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v == _newValue) {
              onCreate();
            } else {
              onSelected(v);
            }
          },
        );
      },
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.label,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? NfTokens.brand.withValues(alpha: 0.2) : NfTokens.elevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? NfTokens.brand : NfTokens.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: NfTokens.brandSoft),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class VentesPage extends ConsumerStatefulWidget {
  const VentesPage({super.key});

  @override
  ConsumerState<VentesPage> createState() => _VentesPageState();
}

class _VentesPageState extends ConsumerState<VentesPage> {
  List<Map<String, dynamic>> ops = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiClientProvider).get<List>(
            '/operations?type=vente',
            parse: (d) => d as List,
          );
      setState(() {
        ops = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      setState(() => ops = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(ledgerRevisionProvider, (_, _) => _load());
    final fmt = NumberFormat.decimalPattern('fr');
    final total = ops.fold<int>(0, (s, o) => s + (o['amountFcfa'] as int? ?? 0));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cahier · ventes'),
        actions: [
          IconButton(
            onPressed: () => context.push('/app/enregistrer'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${fmt.format(total)} FCFA',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: NfTokens.brandSoft,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (ops.isEmpty)
              Text('Aucune vente', style: TextStyle(color: NfTokens.textMute))
            else
              ...ops.map(
                (op) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(op['label']?.toString() ?? 'Vente'),
                  subtitle: Text(
                    op['dateOperation']?.toString() ?? op['createdAt']?.toString() ?? '',
                    style: TextStyle(color: NfTokens.textMute, fontSize: 12),
                  ),
                  trailing: Text(
                    '+${fmt.format(op['amountFcfa'] ?? 0)}',
                    style: const TextStyle(color: NfTokens.ok, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DettesPage extends ConsumerStatefulWidget {
  const DettesPage({super.key});

  @override
  ConsumerState<DettesPage> createState() => _DettesPageState();
}

class _DettesPageState extends ConsumerState<DettesPage> {
  List<Map<String, dynamic>> ops = [];
  String? busyId;
  bool fromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiClientProvider).get<List>(
            '/operations?type=creance',
            parse: (d) => d as List,
          );
      final mapped = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((o) {
            final s = o['statutCreance']?.toString();
            return s == null || s == 'ouverte' || s == 'en_retard';
          })
          .toList();
      await ref.read(localCacheProvider).putList(
            LocalCacheKeys.operations,
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
      if (!mounted) return;
      setState(() {
        ops = mapped;
        fromCache = false;
      });
    } catch (_) {
      final cached = ref
          .read(localCacheProvider)
          .getList(LocalCacheKeys.operations)
          .where((o) {
            if (o['type']?.toString() != 'creance') return false;
            final s = o['statutCreance']?.toString();
            return s == null || s == 'ouverte' || s == 'en_retard';
          })
          .toList();
      if (!mounted) return;
      setState(() {
        ops = cached;
        fromCache = true;
      });
    }
  }

  int _remaining(Map<String, dynamic> op) {
    final total = op['remainingFcfa'] as int? ??
        ((op['amountFcfa'] as int? ?? 0) -
            (op['montantRegleFcfa'] as int? ??
                op['amountSettledFcfa'] as int? ??
                0));
    return total < 0 ? 0 : total;
  }

  Future<void> _settle(String id, {int? amountFcfa}) async {
    setState(() => busyId = id);
    final mutationId = OfflineQueue.newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'operationId': id,
      if (amountFcfa != null) 'amountFcfa': amountFcfa,
    };
    try {
      await ref.read(apiClientProvider).post(
            '/operations/$id/settle',
            data: {if (amountFcfa != null) 'amountFcfa': amountFcfa},
          );
      ref.read(ledgerRevisionProvider.notifier).state++;
      await _load();
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        await ref.read(offlineQueueProvider).enqueue(
              QueuedMutation(
                clientMutationId: mutationId,
                kind: 'settle_creance',
                payload: payload,
                createdAt: createdAt,
              ),
            );
        await ref.read(syncServiceProvider).refreshCount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.read(nfStringsProvider)('savedOffline'))),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _settlePartial(Map<String, dynamic> op) async {
    final id = op['id']?.toString() ?? '';
    final reste = _remaining(op);
    final ctrl = TextEditingController(text: '$reste');
    final t = ref.read(nfStringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('settlePartial')),
        content: SingleChildScrollView(
          child: NfKeypadAmountField(controller: ctrl, label: t('amount')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('deny')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = int.tryParse(ctrl.text.replaceAll(RegExp(r'\s'), '')) ?? 0;
    if (amount <= 0) return;
    await _settle(id, amountFcfa: amount);
  }

  Future<void> _remind(String id) async {
    setState(() => busyId = id);
    final t = ref.read(nfStringsProvider);
    try {
      await ref.read(apiClientProvider).post('/operations/$id/remind');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('reminderSent'))),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _changeDue(Map<String, dynamic> op) async {
    final id = op['id']?.toString() ?? '';
    final current = DateTime.tryParse(op['dueAt']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(DateTime.now()) ? DateTime.now() : current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() => busyId = id);
    try {
      await ref.read(apiClientProvider).patch(
            '/operations/$id/due',
            data: {'dueAt': picked.toUtc().toIso8601String()},
          );
      ref.read(ledgerRevisionProvider.notifier).state++;
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(ledgerRevisionProvider, (_, _) => _load());
    final fmt = NumberFormat.decimalPattern('fr');
    final t = ref.watch(nfStringsProvider);
    final total = ops.fold<int>(0, (s, o) => s + _remaining(o));
    return Scaffold(
      appBar: AppBar(title: Text(t('debts'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${t('toCollect')} · ${fmt.format(total)} FCFA',
              style: TextStyle(color: NfTokens.warn, fontWeight: FontWeight.w700),
            ),
            if (fromCache)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t('offlineCache'),
                  style: TextStyle(color: NfTokens.textMute, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            if (ops.isEmpty)
              Text(t('noOpenDebts'), style: TextStyle(color: NfTokens.textMute))
            else
              ...ops.map((op) {
                final id = op['id']?.toString() ?? '';
                final reste = _remaining(op);
                final overdue = op['statutCreance']?.toString() == 'en_retard';
                final due = op['dueAt']?.toString();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                op['clientName']?.toString() ?? 'Client',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              fmt.format(reste),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          overdue
                              ? t('overdue')
                              : (due != null
                                  ? '${t('dueDate')} · ${due.substring(0, 10)}'
                                  : t('openDebt')),
                          style: TextStyle(
                            color: overdue ? NfTokens.danger : NfTokens.textMute,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed:
                                  busyId == id ? null : () => _settle(id),
                              child: Text(busyId == id ? '…' : t('confirm')),
                            ),
                            TextButton(
                              onPressed: busyId == id
                                  ? null
                                  : () => _settlePartial(op),
                              child: Text(t('settlePartial')),
                            ),
                            TextButton(
                              onPressed:
                                  busyId == id ? null : () => _remind(id),
                              child: Text(t('remind')),
                            ),
                            TextButton(
                              onPressed: busyId == id
                                  ? null
                                  : () => _changeDue(op),
                              child: Text(t('dueDate')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
