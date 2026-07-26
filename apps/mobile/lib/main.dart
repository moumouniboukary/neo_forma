import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/offline/local_cache.dart';
import 'core/offline/queue.dart';
import 'core/theme/tokens.dart';
import 'core/l10n/locale_provider.dart';
import 'core/notifications/notification_service.dart';
import 'features/sync/sync_service.dart';
import 'router.dart';

/// Mappe la langue interface (fr | mr | dl | ff) vers une [Locale] Material
/// supportée. Mooré / Dioula / Fulfuldé n'ont pas de délégué Material officiel
/// : on garde le rendu système en français, seuls les libellés `NfStrings`
/// (via [nfStringsProvider]) restent dans la langue choisie.
Locale _materialLocaleFor(String lang) {
  switch (lang) {
    case 'mr':
    case 'dl':
    case 'ff':
    case 'fr':
    default:
      return const Locale('fr', 'FR');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final queue = OfflineQueue();
  await queue.init();
  final cache = LocalCache();
  await cache.init();
  await NotificationService.instance.init();

  runApp(
    ProviderScope(
      overrides: [
        offlineQueueProvider.overrideWithValue(queue),
        localCacheProvider.overrideWithValue(cache),
      ],
      child: const NeoFormaApp(),
    ),
  );
}

class NeoFormaApp extends ConsumerWidget {
  const NeoFormaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // White-label : charge /branding (no-op si hors ligne).
    final branding = ref.watch(brandingProvider);
    final router = ref.watch(routerProvider);
    final uxPrefs = ref.watch(uxPrefsProvider);
    final themePref = uxPrefs.theme;
    NfTokens.applyThemeMode(themePref);
    final themeMode =
        themePref == 'light' ? ThemeMode.light : ThemeMode.dark;
    return MaterialApp.router(
      key: ValueKey(
        'brand:${branding.hasValue ? NfTokens.appName : 'loading'}:$themePref',
      ),
      title: NfTokens.appName,
      debugShowCheckedModeBanner: false,
      locale: _materialLocaleFor(uxPrefs.language),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildNeoFormaTheme(Brightness.light),
      darkTheme: buildNeoFormaTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
