import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // إضافات Firebase
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    // تأكد أن هذا المعرف يطابق ما في مشروعك
    namespace = "com.example.edu_vantage_app"
    
    // ✅ تم التحديث للإصدار 36 بناءً على متطلبات سجلات البناء (Build Logs)
    compileSdk = 36 

    defaultConfig {
        applicationId = "com.example.edu_vantage_app"
        minSdk = 24
        targetSdk = 36 // ✅ تم التحديث للإصدار 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            // ✅ القراءة من متغيرات البيئة بأسماء مطابقة تماماً لصور الأسرار (Secrets)
            // استخدام System.getenv يضمن قراءة الرموز الخاصة مثل # بشكل سليم
            keyAlias = System.getenv("KEY_ALIAS") ?: ""
            keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            storePassword = System.getenv("STORE_PASSWORD") ?: "" 
            
            // الملف يتم إنشاؤه بواسطة الأتمتة داخل مجلد app
            storeFile = file("upload-keystore.jks")
        }
    }

    buildTypes {
        release {
            // ربط إعدادات التوقيع بنسخة الـ Release
            signingConfig = signingConfigs.getByName("release")
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    implementation("androidx.multidex:multidex:2.0.1")
}
