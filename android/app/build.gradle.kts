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
            // ✅ القراءة من متغيرات البيئة بأسماء مطابقة تماماً للأسرار في الصورة
            // استخدام .trim() يحل مشكلة الرموز الخاصة والمسافات الخفية
            keyAlias = System.getenv("KEY_ALIAS")?.trim() ?: ""
            keyPassword = System.getenv("KEY_PASSWORD")?.trim() ?: ""
            storePassword = System.getenv("STORE_PASSWORD")?.trim() ?: "" 
            
            // الملف يتم إنشاؤه بواسطة الأتمتة داخل مجلد app مباشرة
            storeFile = file("upload-keystore.jks")
        }
    }

    buildTypes {
        release {
            // ربط التوقيع بالنسخة النهائية
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
