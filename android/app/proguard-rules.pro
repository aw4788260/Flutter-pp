# الحفاظ على مكتبات FFmpeg Kit
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.smartexception.** { *; }

# الحفاظ على توابع الـ Native
-keepattributes *Annotation*
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Flutter Local Notifications & Gson Fix ---
# هذه القواعد ضرورية لمنع حذف الكلاسات التي تستخدمها مكتبة الإشعارات في وضع Release
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keepattributes Signature
-keepattributes *Annotation*
