import 'dart:io';
// We alias the plugin to 'fln' to ensure we use the correct types
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import 'package:commit/database/database.dart';
import 'package:commit/repositories/habit_repository.dart';

class NotificationService {
  final fln.FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      fln.FlutterLocalNotificationsPlugin();
  final HabitRepository _habitRepository;

  NotificationService(this._habitRepository);

  Future<void> init() async {
    tz_data.initializeTimeZones();

    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      print('Could not get local timezone: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const fln.AndroidInitializationSettings initializationSettingsAndroid =
        fln.AndroidInitializationSettings('@mipmap/ic_launcher');

    final fln.DarwinInitializationSettings initializationSettingsIOS =
        fln.DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final fln.InitializationSettings initializationSettings =
        fln.InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final fln.AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              fln.AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              fln.IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  Future<void> scheduleNotificationForHabit(Habit habit) async {
    await cancelNotificationsForHabit(habit.id);

    if (habit.reminderHour == null ||
        habit.reminderMinute == null ||
        habit.reminderDays == null ||
        habit.reminderDays!.isEmpty) {
      return;
    }

    final List<int> reminderDays = habit.reminderDays!
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereNotNull()
        .toList();

    if (reminderDays.isEmpty) return;

    final String notificationMessage =
        habit.notificationText != null && habit.notificationText!.isNotEmpty
            ? habit.notificationText!
            : 'Time to check off ${habit.name}!';

    const fln.AndroidNotificationDetails androidPlatformChannelSpecifics =
        fln.AndroidNotificationDetails(
      'habit_tracker_channel',
      'Habit Reminders',
      channelDescription: 'Channel for habit reminder notifications',
      importance: fln.Importance.high,
      priority: fln.Priority.high,
    );

    const fln.DarwinNotificationDetails iOSPlatformChannelSpecifics =
        fln.DarwinNotificationDetails();

    const fln.NotificationDetails platformChannelSpecifics =
        fln.NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    for (int day in reminderDays) {
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        habit.reminderHour!,
        habit.reminderMinute!,
      );

      while (scheduledDate.weekday != day) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      // If the scheduled time for today has already passed, schedule for next week
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }

      // Check if the habit is already logged for the scheduled date
      final isLogged = await _habitRepository.isHabitLoggedOnDate(habit.id, scheduledDate);
      if (isLogged) {
        // If already logged, skip this notification
        continue;
      }

      final int notificationId = (habit.id * 100) + day;

      final fln.AndroidScheduleMode androidMode = 
        fln.AndroidScheduleMode.exactAllowWhileIdle;

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
            notificationId,
            'Habit Reminder',
            notificationMessage,
            scheduledDate,
            platformChannelSpecifics,
            androidScheduleMode: androidMode,
            // uiLocalNotificationDateInterpretation: interpretation, // Pass the variable
            matchDateTimeComponents: fln.DateTimeComponents.dayOfWeekAndTime,
            );
      } catch (e) {
        print("Error scheduling notification for ID $notificationId: $e");
      }

    /*
      // This is the call that was failing.
      // With the 'fln' alias, we ensure we are using the correct Enum types.
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        'Habit Reminder',
        notificationMessage,
        scheduledDate,
        platformChannelSpecifics,
        // These parameters are MANDATORY in v19.5.0
        androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            fln.UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: fln.DateTimeComponents.dayOfWeekAndTime,
      );
      */
    }
  }

  Future<void> cancelNotificationsForHabit(int? habitId) async {
    if (habitId == null) return;
    for (int day = 1; day <= 7; day++) {
      final int notificationId = (habitId * 100) + day;
      await flutterLocalNotificationsPlugin.cancel(notificationId);
    }
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
