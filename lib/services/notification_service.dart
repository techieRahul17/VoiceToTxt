import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,

    );
    
    // Windows typically doesn't need much setup for basic notifications via this plugin but 
    // it's good to have the Linux/Windows init if supported. 
    // For now we focus on mobile.

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        debugPrint("Notification tapped: ${response.payload}");
      },
    );
  }

  Future<void> requestPermissions() async {
    final bool? result = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    debugPrint("Notification permission granted: $result");
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? audioPath,
  }) async {
    try {
      // Create a unique channel for the specific sound if provided
      // Android 8.0+ requires channels to be created with the sound upfront.
      // If audioPath is provided, we create a channel specifically for it.
      String channelId = 'voice_flow_channel_default';
      String channelName = 'VoiceFlow Reminders';
      
      AndroidNotificationDetails androidDetails;

      if (audioPath != null && audioPath.isNotEmpty) {
        // Use a hash of the path to generate a consistent channel ID for this sound
        final soundHash = audioPath.hashCode;
        channelId = 'voice_flow_channel_$soundHash';
        channelName = 'VoiceFlow Custom Sound';
        
        androidDetails = AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'Channel for VoiceFlow activity reminders with custom sound',
          importance: Importance.max,
          priority: Priority.high,
          sound: UriAndroidNotificationSound(audioPath),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );
      } else {
        androidDetails = const AndroidNotificationDetails(
          'voice_flow_channel',
          'VoiceFlow Reminders',
          channelDescription: 'Channel for VoiceFlow activity reminders',
          importance: Importance.max,
          priority: Priority.high,
        );
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint("Scheduled notification $id for $scheduledDate with audio: $audioPath");
    } catch (e) {
      debugPrint("Error scheduling notification: $e");
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }
}
