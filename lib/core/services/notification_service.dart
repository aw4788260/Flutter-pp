import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // إعدادات أندرويد
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // إعدادات iOS (اختيارية إذا كنت ستدعمها لاحقاً)
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // هنا يمكنك التعامل مع الضغط على الإشعار
      },
    );
  }

  // ✅ دالة إلغاء إشعار محدد
  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      // تجاهل الأخطاء البسيطة هنا
    }
  }

  // ✅✅ الدالة المفقودة: إلغاء كل الإشعارات
  Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to cancel all notifications');
    }
  }

  // دالة إظهار إشعار التقدم (Progress)
  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_channel', // id
      'Downloads', // name
      channelDescription: 'Notifications for file downloads',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      onlyAlertOnce: true, // يمنع التنبيه الصوتي المتكرر مع كل تحديث
      ongoing: true, // يمنع المستخدم من حذف الإشعار بالسحب
      autoCancel: false,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  // دالة إظهار إشعار اكتمال التحميل
  Future<void> showCompletionNotification({
    required int id,
    required String title,
    required bool isSuccess,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_completed_channel',
      'Download Completed',
      channelDescription: 'Notifications for completed downloads',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      ongoing: false,
      autoCancel: true,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      isSuccess ? 'Download Complete' : 'Download Failed',
      isSuccess ? '$title has been downloaded.' : 'Failed to download $title.',
      platformChannelSpecifics,
    );
  }
}
