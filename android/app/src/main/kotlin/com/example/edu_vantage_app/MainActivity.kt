package com.example.edu_vantage_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // إضافة حماية الشاشة (منع التصوير)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
