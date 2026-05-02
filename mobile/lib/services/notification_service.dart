import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'pomodoro_timer';
  static const _idRunning = 1;
  static const _idComplete = 2;

  static const _channelDetails = AndroidNotificationDetails(
    _channelId,
    'Pomodoro Timer',
    channelDescription: 'Timer status and completion alerts',
    importance: Importance.max,
    priority: Priority.max,
    enableVibration: true,
    playSound: true,
  );

  static Future<void> init() async {
    tz_data.initializeTimeZones();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    );
    await _plugin.initialize(initSettings);

    if (Platform.isAndroid) {
      final impl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await impl?.requestNotificationsPermission();
      await impl?.requestExactAlarmsPermission();
    }
  }

  // Persistent silent notification shown while timer is running.
  static Future<void> showRunning(DateTime endTime, String label) async {
    final h = endTime.hour.toString().padLeft(2, '0');
    final m = endTime.minute.toString().padLeft(2, '0');
    await _plugin.show(
      _idRunning,
      '$label in progress',
      'Ends at $h:$m',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Pomodoro Timer',
          channelDescription: 'Timer status and completion alerts',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          silent: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
    );
  }

  // OS-level scheduled notification — fires even if the app is killed.
  static Future<void> scheduleComplete(DateTime endTime, String label) async {
    await _plugin.cancel(_idComplete);
    // Convert local time → UTC TZDateTime so the alarm fires at the right moment
    // regardless of which timezone flutter_local_notifications resolves for 'local'.
    final utc = endTime.toUtc();
    final scheduled = tz.TZDateTime.utc(
        utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);

    await _plugin.zonedSchedule(
      _idComplete,
      '$label complete!',
      _nextHint(label),
      scheduled,
      const NotificationDetails(
        android: _channelDetails,
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // Immediate notification + haptic — used when the timer fires while the app
  // is in the foreground (the scheduled notification is pre-cancelled in that case).
  static Future<void> showComplete(String label) async {
    HapticFeedback.heavyImpact();
    await _plugin.show(
      _idComplete,
      '$label complete!',
      _nextHint(label),
      const NotificationDetails(
        android: _channelDetails,
        linux: LinuxNotificationDetails(),
      ),
    );
  }

  static Future<void> cancelRunning() => _plugin.cancel(_idRunning);
  static Future<void> cancelAll() => _plugin.cancelAll();

  static String _nextHint(String label) =>
      label == 'Focus' ? 'Time for a break.' : 'Ready to focus again?';
}
