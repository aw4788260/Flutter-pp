package com.example.edu_vantage_app

import android.os.Bundle // ضروري جداً للدالة onCreate
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ✅ 1. منع تسجيل الفيديو وأخذ لقطات الشاشة (FLAG_SECURE)
        // وضعه في onCreate يضمن تنفيذه فوراً عند بناء النافذة
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)

        // ✅ 2. منع تسجيل الصوت الداخلي (Internal Audio)
        // تطبيق المنطق الموجود في كود الجافا (استخدام الرقم 3 مباشرة)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                // الرقم 3 يعني ALLOW_CAPTURE_BY_NONE
                audioManager.allowedCapturePolicy = 3 
            } catch (e: Exception) {
                // تجاهل الأخطاء لمنع توقف التطبيق
            }
        }
    }

    override fun onDestroy() {
        // 3. حذف الإشعارات عند إغلاق التطبيق
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        } catch (e: Exception) {
            // تجاهل الخطأ
        }
        
        super.onDestroy()
    }
}
