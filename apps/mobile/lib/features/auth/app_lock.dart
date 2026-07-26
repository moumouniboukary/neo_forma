import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_numeric_keypad.dart';

/// Verrouillage applicatif : PIN local (déverrouillage rapide, indépendant du
/// PIN serveur) + biométrie optionnelle. Blocage 5 min après 5 échecs.
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.biometricAvailable = false,
    this.biometricEnabled = false,
  });

  /// Un PIN local de déverrouillage rapide a été configuré.
  final bool enabled;
  final bool locked;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final bool biometricAvailable;
  final bool biometricEnabled;

  bool get isLockedOut =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
    bool? biometricAvailable,
    bool? biometricEnabled,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier() : super(const AppLockState()) {
    _bootstrap();
  }

  static const maxAttempts = 5;
  static const lockDuration = Duration(minutes: 5);

  static const _pinKey = 'neoforma.applock.pin';
  static const _biometricKey = 'neoforma.applock.biometric';
  static const _failCountKey = 'neoforma.applock.failCount';
  static const _lockedUntilKey = 'neoforma.applock.lockedUntil';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<void> _bootstrap() async {
    final pin = await _storage.read(key: _pinKey);
    final bioEnabled = (await _storage.read(key: _biometricKey)) == '1';
    var bioAvailable = false;
    try {
      bioAvailable =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      bioAvailable = false;
    }
    final failCount =
        int.tryParse(await _storage.read(key: _failCountKey) ?? '0') ?? 0;
    final lockedUntilRaw = await _storage.read(key: _lockedUntilKey);
    final lockedUntil = lockedUntilRaw != null
        ? DateTime.tryParse(lockedUntilRaw)
        : null;

    state = state.copyWith(
      enabled: pin != null,
      locked: pin != null,
      failedAttempts: failCount,
      lockedUntil: lockedUntil,
      biometricAvailable: bioAvailable,
      biometricEnabled: bioEnabled,
    );
  }

  /// Enregistre le PIN de déverrouillage rapide (appelé après login/register).
  Future<void> setupPin(String pin) async {
    if (pin.length != 4) return;
    await _storage.write(key: _pinKey, value: pin);
    await _storage.write(key: _failCountKey, value: '0');
    await _storage.delete(key: _lockedUntilKey);
    state = state.copyWith(
      enabled: true,
      failedAttempts: 0,
      clearLockedUntil: true,
    );
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _storage.write(key: _biometricKey, value: value ? '1' : '0');
    state = state.copyWith(biometricEnabled: value);
  }

  /// Verrouille l'app (retour de background, etc). No-op si aucun PIN local.
  void lock() {
    if (!state.enabled || state.locked) return;
    state = state.copyWith(locked: true);
  }

  Future<bool> verifyPin(String pin) async {
    if (state.isLockedOut) return false;
    final stored = await _storage.read(key: _pinKey);
    if (stored != null && stored == pin) {
      await _storage.write(key: _failCountKey, value: '0');
      await _storage.delete(key: _lockedUntilKey);
      state = state.copyWith(
        locked: false,
        failedAttempts: 0,
        clearLockedUntil: true,
      );
      return true;
    }
    final attempts = state.failedAttempts + 1;
    if (attempts >= maxAttempts) {
      final until = DateTime.now().add(lockDuration);
      await _storage.write(key: _lockedUntilKey, value: until.toIso8601String());
      await _storage.write(key: _failCountKey, value: '0');
      state = state.copyWith(failedAttempts: 0, lockedUntil: until);
    } else {
      await _storage.write(key: _failCountKey, value: '$attempts');
      state = state.copyWith(failedAttempts: attempts);
    }
    return false;
  }

  Future<bool> authenticateBiometric() async {
    if (!state.biometricEnabled || !state.biometricAvailable) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Déverrouiller NeoForma',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok) {
        state = state.copyWith(locked: false, failedAttempts: 0);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Purge tout état local (déconnexion / suppression compte).
  Future<void> clear() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _failCountKey);
    await _storage.delete(key: _lockedUntilKey);
    await _storage.delete(key: _biometricKey);
    state = const AppLockState(
      biometricAvailable: false,
      biometricEnabled: false,
    );
  }
}

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>((
  ref,
) {
  return AppLockNotifier();
});

/// Enveloppe le contenu applicatif : verrouille au retour de l'arrière-plan
/// et affiche l'écran de saisie PIN / biométrie tant que verrouillé.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(appLockProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (lock.enabled && lock.locked) {
      return const _AppLockScreen();
    }
    return widget.child;
  }
}

class _AppLockScreen extends ConsumerStatefulWidget {
  const _AppLockScreen();

  @override
  ConsumerState<_AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<_AppLockScreen> {
  String pin = '';
  String? error;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    final lock = ref.read(appLockProvider);
    if (!lock.biometricEnabled || !lock.biometricAvailable) return;
    await ref.read(appLockProvider.notifier).authenticateBiometric();
  }

  Future<void> _submit() async {
    if (pin.length != 4 || checking) return;
    setState(() => checking = true);
    final ok = await ref.read(appLockProvider.notifier).verifyPin(pin);
    if (!mounted) return;
    final t = ref.read(nfStringsProvider);
    setState(() {
      checking = false;
      pin = '';
      error = ok ? null : t('wrongPin');
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final t = ref.watch(nfStringsProvider);
    final lockedOut = lock.isLockedOut;

    return Scaffold(
      backgroundColor: NfTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.lock_outline, size: 48, color: NfTokens.brand),
              const SizedBox(height: 16),
              Text(
                t('appLocked'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (lockedOut)
                Text(
                  t('lockedTryLater'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NfTokens.danger),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? NfTokens.brand : NfTokens.elevated,
                        border: Border.all(color: NfTokens.line),
                      ),
                    );
                  }),
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: NfTokens.danger)),
              ],
              const Spacer(),
              if (!lockedOut)
                NfNumericKeypad(
                  onDigit: (d) {
                    if (pin.length >= 4 || checking) return;
                    HapticFeedback.selectionClick();
                    setState(() => pin += d);
                    if (pin.length == 4) _submit();
                  },
                  onBackspace: () {
                    if (pin.isEmpty) return;
                    setState(() => pin = pin.substring(0, pin.length - 1));
                  },
                  onClear: () => setState(() => pin = ''),
                ),
              if (lock.biometricEnabled && lock.biometricAvailable) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(t('useBiometric')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
