package com.example.edu_vantage_app

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager // ✅ مكتبة الصوت الضرورية
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. منع تصوير الشاشة (الفيديو يظهر أسود + منع السكرين شوت)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)

        // 2. منع التقاط الصوت الداخلي (نفس منطق تطبيق الجافا بالضبط)
        // يعمل فقط على أندرويد 10 (API 29) وما فوق لأن الخاصية غير موجودة قبله
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            // القيمة 3 في الجافا تعادل AudioManager.ALLOW_CAPTURE_BY_NONE في الكوتلن
            audioManager.allowedCapturePolicy = AudioManager.ALLOW_CAPTURE_BY_NONE
        }
    }

    override fun onDestroy() {
        // حذف الإشعارات عند إغلاق التطبيق نهائياً
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
        
        super.onDestroy()
    }
}
