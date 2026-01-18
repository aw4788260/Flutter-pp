package com.example.edu_vantage_app

import android.app.NotificationManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onDestroy() {
        // 1. استدعاء مدير الإشعارات
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // 2. حذف جميع الإشعارات الخاصة بالتطبيق فوراً عند الإغلاق
        notificationManager.cancelAll()
        
        super.onDestroy()
    }
}
