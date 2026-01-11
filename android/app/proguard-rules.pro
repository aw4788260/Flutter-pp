# الحفاظ على مكتبات FFmpeg Kit
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.smartexception.** { *; }

# الحفاظ على توابع الـ Native
-keepattributes *Annotation*
-keepclasseswithmembernames class * {
    native <methods>;
}
