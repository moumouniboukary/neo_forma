import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/brand.dart';
import 'core/offline/local_cache.dart';
import 'core/offline/queue.dart';
import 'core/theme/tokens.dart';
import 'core/l10n/locale_provider.dart';
import 'core/notifications/notification_service.dart';
import 'features/auth/brand_splash.dart';
import 'features/sync/sync_service.dart';
import 'router.dart';

/// Garde heure / batterie / nav visibles (évite le mode immersif après splash).
void _ensureSystemBarsVisible({Brightness brightness = Brightness.light}) {
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  final light = brightness == Brightness.light;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: light ? const Color(0xFFF2F8F5) : const Color(0xFF07140F),
      systemNavigationBarIconBrightness:
          light ? Brightness.dark : Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}

Locale _materialLocaleFor(String lang) {
  switch (lang) {
    case 'mr':
    case 'fr':
    default:
      return const Locale('fr', 'FR');
  }
}

ThemeMode _themeModeFor(String themePref) {
  switch (themePref) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Splash marque (blanc → logo + nom), initialise Hive/etc. en parallèle.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NfTokens.appName = kAppName;
  _ensureSystemBarsVisible();
  // Pas de ProviderScope ici : les overrides (cache/queue) doivent être sur le
  // scope racine. Un scope imbriqué cassait clientsProvider / stock / etc.
  runApp(const _BootGate());
}

class _BootServices {
  _BootServices(this.queue, this.cache);
  final OfflineQueue queue;
  final LocalCache cache;
}

class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  late final Future<_BootServices> _boot;
  bool _splashMinDone = false;
  _BootServices? _services;

  @override
  void initState() {
    super.initState();
    _boot = _loadServices();
    _boot.then((s) {
      if (!mounted) return;
      setState(() => _services = s);
    });
    // Durée totale gérée dans BrandSplashView (1 s blanc + marque).
  }

  Future<_BootServices> _loadServices() async {
    final queue = OfflineQueue();
    final cache = LocalCache();
    await Future.wait([
      initializeDateFormatting('fr_FR'),
      queue.init(),
      cache.init(),
      NotificationService.instance.init(),
    ]);
    return _BootServices(queue, cache);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _services != null && _splashMinDone;
    if (!ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BrandSplashView(
          key: const ValueKey('boot-splash'),
          onFinished: () {
            if (!mounted) return;
            setState(() => _splashMinDone = true);
          },
        ),
      );
    }

    return ProviderScope(
      overrides: [
        offlineQueueProvider.overrideWithValue(_services!.queue),
        localCacheProvider.overrideWithValue(_services!.cache),
      ],
      child: const NeoFormaApp(),
    );
  }
}

class NeoFormaApp extends ConsumerStatefulWidget {
  const NeoFormaApp({super.key});

  @override
  ConsumerState<NeoFormaApp> createState() => _NeoFormaAppState();
}

class _NeoFormaAppState extends ConsumerState<NeoFormaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureSystemBarsVisible(brightness: NfTokens.brightness);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _resyncThemeTokens() {
    final themePref = ref.read(uxPrefsProvider).theme;
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Mode « Téléphone » seulement : clair/sombre fixes ne bougent pas au resume.
    if (themePref == 'system') {
      ref.read(uxPrefsProvider.notifier).syncPlatformBrightness(platform);
    } else {
      NfTokens.applyThemeMode(themePref, platformBrightness: platform);
    }
  }

  @override
  void didChangePlatformBrightness() {
    _resyncThemeTokens();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour au premier plan : resync (évite un thème sombre « collé »
    // après veille / dialog système / économiseur d’énergie).
    if (state == AppLifecycleState.resumed) {
      _resyncThemeTokens();
      _ensureSystemBarsVisible(brightness: NfTokens.brightness);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // White-label : charge /branding (pas de remount MaterialApp).
    ref.watch(brandingProvider);
    final router = ref.watch(routerProvider);
    final uxPrefs = ref.watch(uxPrefsProvider);
    final themePref = uxPrefs.theme;
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Aligner les tokens AVANT le build des enfants (évite clair/sombre mélangés).
    final resolved = NfTokens.resolveBrightness(
      themePref,
      platformBrightness: platform,
    );
    NfTokens.syncFromThemeBrightness(resolved);
    final themeMode = _themeModeFor(themePref);

    return MaterialApp.router(
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
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        NfTokens.syncFromThemeBrightness(brightness);
        final light = brightness == Brightness.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                light ? Brightness.dark : Brightness.light,
            statusBarBrightness: light ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness:
                light ? Brightness.dark : Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
