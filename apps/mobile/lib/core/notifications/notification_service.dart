import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/client.dart';

/// Notifications locales + enregistrement jeton FCM (si fourni).
///
/// Push distant : obtenir un token Firebase côté app (voir docs/pilot-ops.md),
/// puis appeler [registerPushToken]. Sans Firebase configuré, reste en local.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _registeredToken;

  Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosInit = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService.init: $e');
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    try {
      const androidDetails = AndroidNotificationDetails(
        'neoforma_default',
        'NeoForma',
        channelDescription: 'Notifications NeoForma',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(id, title, body, details);
    } catch (e) {
      debugPrint('NotificationService.show: $e');
    }
  }

  /// Enregistre le jeton FCM auprès de l'API (`POST /devices/push-token`).
  Future<void> registerPushToken(
    ApiClient api, {
    required String token,
    String platform = 'android',
  }) async {
    if (token.isEmpty || token == _registeredToken) return;
    try {
      await api.post('/devices/push-token', data: {
        'token': token,
        'platform': platform,
      });
      _registeredToken = token;
      debugPrint('FCM token registered');
    } catch (e) {
      debugPrint('registerPushToken: $e');
    }
  }
}
