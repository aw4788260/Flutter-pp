package com.example.edu_vantage_app

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. منع تسجيل الفيديو وأخذ لقطات الشاشة (FLAG_SECURE)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)

        // 2. منع تسجيل الصوت الداخلي (Internal Audio)
        // يعمل فقط في أندرويد 10 (API 29) وما فوق
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            
            // استخدام الرقم 3 مباشرة كما في كود الجافا لتجنب خطأ Unresolved reference
            // الرقم 3 يعني: AudioManager.ALLOW_CAPTURE_BY_NONE
            audioManager.allowedCapturePolicy = 3 
        }
    }

    override fun onDestroy() {
        // 3. حذف جميع الإشعارات الخاصة بالتطبيق فوراً عند الإغلاق
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        } catch (e: Exception) {
            // تجاهل أي خطأ أثناء الإغلاق
        }
        
        super.onDestroy()
    }
}
