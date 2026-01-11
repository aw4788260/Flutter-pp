import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.example.edu_vantage_app"
    compileSdk = 36 

    defaultConfig {
        applicationId = "com.example.edu_vantage_app"
        minSdk = 24
        targetSdk = 36 
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            // قراءة المتغيرات من البيئة (للأتمتة عبر GitHub Actions)
            keyAlias = System.getenv("KEY_ALIAS")?.trim() ?: ""
            keyPassword = System.getenv("KEY_PASSWORD")?.trim() ?: ""
            storePassword = System.getenv("STORE_PASSWORD")?.trim() ?: "" 
            
            // ملف التوقيع يتم إنشاؤه أثناء البناء
            storeFile = file("upload-keystore.jks")
        }
    }

    buildTypes {
        release {
            // إعدادات التوقيع
            signingConfig = signingConfigs.getByName("release")
            
            // إعدادات التصغير والحماية
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            
            // رفع رموز التصحيح لـ NDK (لحل مشاكل C++ في Crashlytics)
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                nativeSymbolUploadEnabled = true
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // ✅✅✅ هذا هو الجزء الجديد والهام جداً لحل مشكلة FFmpeg ✅✅✅
    packaging {
        jniLibs {
            // يمنع تضارب المكتبات المشتركة عند استخدام FFmpeg مع مكتبات أخرى
            pickFirst("lib/x86/libc++_shared.so")
            pickFirst("lib/x86_64/libc++_shared.so")
            pickFirst("lib/armeabi-v7a/libc++_shared.so")
            pickFirst("lib/arm64-v8a/libc++_shared.so")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    // مكتبة NDK لالتقاط أخطاء FFmpeg
    implementation("com.google.firebase:firebase-crashlytics-ndk:18.6.0")
    
    implementation("androidx.multidex:multidex:2.0.1")
}
