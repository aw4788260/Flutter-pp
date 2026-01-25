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

        // ✅ 1. منع تسجيل الفيديو (الشاشة تظهر سوداء) + منع لقطات الشاشة (Screenshots)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)

        // ✅ 2. منع تسجيل الصوت الداخلي (Internal Audio) - يعمل فقط في أندرويد 10 (API 29) وما فوق
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.allowedCapturePolicy = AudioManager.ALLOW_CAPTURE_BY_NONE
        }
    }

    override fun onDestroy() {
        // ✅ 3. حذف جميع الإشعارات الخاصة بالتطبيق فوراً عند الإغلاق (Kill App)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
        
        super.onDestroy()
    }
}
