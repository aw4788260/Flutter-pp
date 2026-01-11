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
            keyAlias = System.getenv("KEY_ALIAS")?.trim() ?: ""
            keyPassword = System.getenv("KEY_PASSWORD")?.trim() ?: ""
            storePassword = System.getenv("STORE_PASSWORD")?.trim() ?: "" 
            storeFile = file("upload-keystore.jks")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            
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

    // ✅✅✅ القسم الأهم لحل مشكلة الشاشة السوداء ✅✅✅
    packaging {
        jniLibs {
            // هذا السطر يجبر النظام على فك ضغط المكتبات القديمة مثل FFmpeg
            useLegacyPackaging = true 
            
            // حل تضارب الملفات المكررة
            pickFirst("lib/x86/libc++_shared.so")
            pickFirst("lib/x86_64/libc++_shared.so")
            pickFirst("lib/armeabi-v7a/libc++_shared.so")
            pickFirst("lib/arm64-v8a/libc++_shared.so")
        }
    }

    // ✅ تأكيد إضافي لعدم ضغط ملفات المكتبات
    aaptOptions {
        noCompress("tflite", "lite", "so")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    implementation("com.google.firebase:firebase-crashlytics-ndk:18.6.0")
    implementation("androidx.multidex:multidex:2.0.1")
}
