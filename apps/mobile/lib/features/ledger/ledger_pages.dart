import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/offline/queue.dart';
import '../../core/theme/tokens.dart';
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
  final amountCtrl = TextEditingController(text: '2500');
  final clientCtrl = TextEditingController();
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
      if (type == 'stock') ...{'label': 'Stock', 'natureStock': 'entree'},
      if (type == 'depense') 'label': 'Dépense',
      if (type == 'creance') ...{
        if (selectedClientId != null)
          'clientId': selectedClientId
        else
          'clientName':
              clientCtrl.text.trim().isEmpty ? 'Client' : clientCtrl.text.trim(),
        'dueAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
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
              const Icon(Icons.check_circle, size: 72, color: NfTokens.ok),
              const SizedBox(height: 12),
              Text(
                savedOffline
                    ? 'Enregistré hors ligne — synchronisation au retour du réseau'
                    : 'Synchronisé',
                style: const TextStyle(color: NfTokens.textMute),
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
          ],
          if (type == 'vente' || type == 'depense') ...[
            const SizedBox(height: 16),
            const Text('Canal', style: TextStyle(color: NfTokens.textMute)),
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
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: t('amount'),
              suffixIcon: IconButton(
                tooltip: 'Dicter le montant',
                onPressed: listening ? null : _dictateAmount,
                icon: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  color: listening ? NfTokens.brand : NfTokens.textMute,
                ),
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
              const Text('Aucune vente', style: TextStyle(color: NfTokens.textMute))
            else
              ...ops.map(
                (op) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(op['label']?.toString() ?? 'Vente'),
                  subtitle: Text(
                    op['dateOperation']?.toString() ?? op['createdAt']?.toString() ?? '',
                    style: const TextStyle(color: NfTokens.textMute, fontSize: 12),
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
      setState(() {
        ops = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((o) {
              final s = o['statutCreance']?.toString();
              return s == null || s == 'ouverte' || s == 'en_retard';
            })
            .toList();
      });
    } catch (_) {
      setState(() => ops = []);
    }
  }

  Future<void> _settle(String id) async {
    setState(() => busyId = id);
    try {
      await ref.read(apiClientProvider).post('/operations/$id/settle');
      // Met à jour l'accueil et le cahier (créance réglée = flux entrant).
      ref.read(ledgerRevisionProvider.notifier).state++;
      await _load();
    } finally {
      setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(ledgerRevisionProvider, (_, _) => _load());
    final fmt = NumberFormat.decimalPattern('fr');
    final total = ops.fold<int>(0, (s, o) => s + (o['amountFcfa'] as int? ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('Créances')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'À récupérer · ${fmt.format(total)} FCFA',
              style: const TextStyle(color: NfTokens.warn, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (ops.isEmpty)
              const Text('Aucune créance ouverte', style: TextStyle(color: NfTokens.textMute))
            else
              ...ops.map((op) {
                final id = op['id']?.toString() ?? '';
                return Card(
                  child: ListTile(
                    title: Text(op['clientName']?.toString() ?? 'Client'),
                    subtitle: Text(
                      op['statutCreance']?.toString() == 'en_retard'
                          ? 'En retard'
                          : 'Ouverte',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmt.format(op['amountFcfa'] ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextButton(
                          onPressed: busyId == id ? null : () => _settle(id),
                          child: Text(busyId == id ? '…' : 'Régler'),
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
