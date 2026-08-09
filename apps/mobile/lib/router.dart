import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/app_lock.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/register_forgot.dart';
import 'features/auth/splash_login.dart';
import 'features/home/shell_dashboard.dart';
import 'features/ledger/ledger_data.dart';
import 'features/ledger/ledger_pages.dart';
import 'features/ledger/products_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/score_credit_profile.dart';
import 'features/stock/stock_page.dart';
import 'features/tontine/tontine_page.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

GoRouter createRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (!auth.ready) return null;
      final loc = state.matchedLocation;
      final loggingIn =
          loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/';

      if (!auth.isAuthenticated && !loggingIn) return '/login';
      if (auth.isAuthenticated &&
          (loc == '/' || loc == '/login' || loc == '/register')) {
        return '/app';
      }
      if (auth.needsOnboarding && loc == '/app/score') {
        return '/onboarding';
      }
      if (!auth.needsOnboarding && loc == '/onboarding') {
        return '/app';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) =>
            AppLockGate(child: AppShell(child: child)),
        routes: [
          GoRoute(
            path: '/app',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/app/ventes',
            builder: (context, state) => const VentesPage(),
          ),
          GoRoute(
            path: '/app/depenses',
            builder: (context, state) =>
                const VentesPage(initialTab: 'depense'),
          ),
          GoRoute(
            path: '/app/dettes',
            builder: (context, state) => const DettesPage(),
          ),
          GoRoute(
            path: '/app/profil',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      // Plein écran (hors barre du bas) — siblings du ShellRoute
      GoRoute(
        path: '/app/enregistrer',
        parentNavigatorKey: _rootKey,
        builder: (context, state) {
          final extra = state.extra;
          final preset = extra is SaleProduct ? extra : null;
          return RecordPage(presetProduct: preset);
        },
      ),
      GoRoute(
        path: '/app/produits',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const ProductsPage(),
      ),
      GoRoute(
        path: '/app/score',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const ScorePage(),
      ),
      GoRoute(
        path: '/app/credit',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const CreditPage(),
      ),
      GoRoute(
        path: '/app/stock',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const StockPage(),
      ),
      GoRoute(
        path: '/app/tontine',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const TontinePage(),
      ),
      GoRoute(
        path: '/app/notifications',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const NotificationsPage(),
      ),
    ],
  );
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen<AuthState>(authProvider, (previous, next) {
      notifyListeners();
    });
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) => createRouter(ref));
