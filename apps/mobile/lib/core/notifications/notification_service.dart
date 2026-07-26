import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications locales (push simulé) — affiche une notif système quand
/// une notification in-app non lue arrive (décision crédit, créance en retard…).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
}
