import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/offline/queue.dart';
import 'core/theme/tokens.dart';
import 'features/sync/sync_service.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final queue = OfflineQueue();
  await queue.init();

  runApp(
    ProviderScope(
      overrides: [
        offlineQueueProvider.overrideWithValue(queue),
      ],
      child: const NeoFormaApp(),
    ),
  );
}

class NeoFormaApp extends ConsumerWidget {
  const NeoFormaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'NeoForma',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildNeoFormaTheme(),
      routerConfig: router,
    );
  }
}
