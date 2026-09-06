import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/offline/local_cache.dart';
import '../../core/riverpod_safe.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../auth/app_lock.dart';
import '../sync/sync_service.dart';
import 'credits_section.dart';

/// Préférences UX, sync, sécurité — séparé du profil identité.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late String language;
  late String theme;
  late bool iconMode;
  late bool voiceAssist;
  bool saving = false;
  String? message;
  String? error;
  int queueRevision = 0;
  int _unreadBadge = 0;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(uxPrefsProvider);
    language = prefs.language;
    theme = prefs.theme;
    iconMode = prefs.iconMode;
    voiceAssist = prefs.voiceAssist;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshUnreadBadge();
    });
  }

  void _refreshUnreadBadge() {
    final items =
        ref.read(localCacheProvider).getList(LocalCacheKeys.notifications);
    final n = items.where((e) => e['lu'] != true).length;
    if (!mounted || n == _unreadBadge) return;
    setState(() => _unreadBadge = n);
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
      message = null;
    });
    try {
      await ref.read(uxPrefsProvider.notifier).persist(
            language: language,
            iconMode: iconMode,
            voiceAssist: voiceAssist,
            theme: theme,
          );
      if (!mounted) return;
      final t = ref.read(nfStringsProvider);
      setState(() => message = t('settingsSaved'));
    } catch (_) {
      if (!mounted) return;
      setState(() => error = ref.read(nfStringsProvider)('settingsSaveError'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _ = queueRevision;
    final t = ref.watch(nfStringsProvider);
    final lock = ref.watch(appLockProvider);
    final pending = ref.watch(syncPendingProvider);
    final syncErr = ref.watch(syncErrorProvider);
    final queue = ref.read(offlineQueueProvider);
    final failedItems =
        queue.list().where((m) => m.status == 'failed').toList();
    final failed = failedItems.length;
    final unread = _unreadBadge;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('settings')),
        leading: nfBackButton(context, fallbackLocation: '/app/profil'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t('settingsAppearance'),
            style: TextStyle(
              color: NfTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Text(t('language'), style: TextStyle(color: NfTokens.textMute)),
          const SizedBox(height: 8),
          NfSegmented(
            value: language,
            onChanged: (v) {
              setState(() => language = v);
              scheduleProviderWrite(() {
                ref.read(uxPrefsProvider.notifier).setLanguageLocal(v);
              });
            },
            options: [for (final e in NfStrings.selectableLanguages) e],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: NfTokens.elevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NfTokens.brand),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('theme'),
                  style: TextStyle(
                    color: NfTokens.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: theme,
                  onChanged: (v) {
                    setState(() => theme = v);
                    scheduleProviderWrite(() {
                      ref.read(uxPrefsProvider.notifier).persist(theme: v);
                    });
                  },
                  options: [
                    ('light', t('themeLight')),
                    ('dark', t('themeDark')),
                    ('system', t('themeSystem')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(t('iconMode'), style: TextStyle(color: NfTokens.textMute)),
          const SizedBox(height: 4),
          Text(
            t('iconModeHint'),
            style: TextStyle(color: NfTokens.textMute, fontSize: 13),
          ),
          const SizedBox(height: 8),
          NfSegmented(
            value: iconMode ? 'oui' : 'non',
            onChanged: (v) => setState(() => iconMode = v == 'oui'),
            options: [('oui', t('yes')), ('non', t('no'))],
          ),
          const SizedBox(height: 16),
          Text(t('voiceAssist'), style: TextStyle(color: NfTokens.textMute)),
          const SizedBox(height: 4),
          Text(
            t('voiceAssistHint'),
            style: TextStyle(color: NfTokens.textMute, fontSize: 13),
          ),
          const SizedBox(height: 8),
          NfSegmented(
            value: voiceAssist ? 'oui' : 'non',
            onChanged: (v) {
              setState(() => voiceAssist = v == 'oui');
              if (v == 'oui') {
                ref.read(voiceServiceProvider).speakKey('voiceAssist');
              }
            },
            options: [('oui', t('yes')), ('non', t('no'))],
          ),
          if (voiceAssist) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(t('listen'), style: TextStyle(color: NfTokens.textMute)),
                const NfSpeakButton(labelKey: 'voiceAssist', alwaysShow: true),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(
            t('settingsSecurity'),
            style: TextStyle(
              color: NfTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (lock.biometricAvailable) ...[
            const SizedBox(height: 12),
            Text(t('lock'), style: TextStyle(color: NfTokens.textMute)),
            const SizedBox(height: 8),
            NfSegmented(
              value: lock.biometricEnabled ? 'oui' : 'non',
              onChanged: (v) => ref
                  .read(appLockProvider.notifier)
                  .setBiometricEnabled(v == 'oui'),
              options: [('oui', t('yes')), ('non', t('no'))],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              t('lockUnavailable'),
              style: TextStyle(color: NfTokens.textMute, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            t('settingsTools'),
            style: TextStyle(
              color: NfTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: Text(t('notifications')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: NfTokens.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => context.push('/app/notifications'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              pending > 0
                  ? '${t('offlineQueue')} · ${t.format('offlinePending', {'n': '$pending'})}'
                  : failed > 0
                      ? '${t('offlineQueue')} · ${t.format('offlineFailed', {'n': '$failed'})}'
                      : '${t('offlineQueue')} · ${t('offlineUpToDate')}',
            ),
            subtitle: syncErr != null
                ? Text(syncErr, style: const TextStyle(color: NfTokens.danger))
                : Text(
                    t('offlineQueueHint'),
                    style: TextStyle(color: NfTokens.textMute, fontSize: 12),
                  ),
            trailing: pending > 0 || failed > 0
                ? TextButton(
                    onPressed: () async {
                      await ref.read(syncServiceProvider).flush();
                      setState(() => queueRevision++);
                    },
                    child: Text(t('retrySync')),
                  )
                : null,
          ),
          if (failedItems.isNotEmpty)
            ...failedItems.map(
              (m) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(m.kind, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  m.failReason ?? t('syncFailed'),
                  style: const TextStyle(color: NfTokens.danger, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: t('retrySync'),
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () async {
                        await ref
                            .read(offlineQueueProvider)
                            .retryFailed(m.clientMutationId);
                        await ref.read(syncServiceProvider).flush();
                        setState(() => queueRevision++);
                      },
                    ),
                    IconButton(
                      tooltip: t('discardSync'),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        await ref
                            .read(offlineQueueProvider)
                            .discard(m.clientMutationId);
                        await ref.read(syncServiceProvider).refreshCount();
                        setState(() => queueRevision++);
                      },
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 28),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline, color: NfTokens.brand),
            title: Text(t('aboutHelp')),
            subtitle: Text(t('aboutHelpHint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/app/aide'),
          ),
          const SizedBox(height: 12),
          const NfCreditsSection(),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, style: const TextStyle(color: NfTokens.ok)),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: NfTokens.danger)),
          ],
          const SizedBox(height: 16),
          NfPrimaryButton(
            label: t('save'),
            loading: saving,
            onPressed: saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
