import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ✅ ضروري لـ ThemeMode و ValueNotifier
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/course_model.dart';
import '../../core/services/storage_service.dart';

class AppState {
  // Singleton Pattern
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // البيانات المخزنة
  List<CourseModel> allCourses = []; // للمتجر والشاشة الرئيسية
  Map<String, dynamic>? userData;
  
  List<String> myCourseIds = [];
  List<String> mySubjectIds = [];
  
  // ✅ القائمة الجاهزة للعرض في صفحة "مكتبتي"
  List<Map<String, dynamic>> myLibrary = [];

  // ✅ متغير لتحديد هل المستخدم ضيف أم لا
  bool isGuest = false;

  // ============================================================
  // 🌓 إدارة الثيم (Theme Management) - جديد
  // ============================================================

  // ✅ 1. إضافة متغير لمراقبة الثيم (ValueNotifier) لتحديث الواجهة فورياً
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

  // ✅ 2. دالة ثابتة (Static Getter) لمعرفة هل الوضع الحالي داكن (تستخدمها AppColors)
  static bool get isDark => _instance.themeNotifier.value == ThemeMode.dark;

  // ✅ 3. دالة تهيئة الثيم عند فتح التطبيق (تستدعى في main.dart)
  Future<void> initTheme() async {
    var box = await StorageService.openBox('settings_box');
    // القيمة الافتراضية هي الوضع الداكن (true)
    bool storedIsDark = box.get('is_dark_mode', defaultValue: true);
    themeNotifier.value = storedIsDark ? ThemeMode.dark : ThemeMode.light;
  }

  // ✅ 4. دالة التبديل بين الوضعين (عند ضغط الزر)
  // ⚠️ تم التعديل هنا: تغيير void إلى Future<void> لإصلاح خطأ الـ await
  Future<void> toggleTheme() async {
    bool currentIsDark = themeNotifier.value == ThemeMode.dark;
    
    // عكس القيمة الحالية
    themeNotifier.value = currentIsDark ? ThemeMode.light : ThemeMode.dark;
    
    // حفظ التفضيل الجديد في التخزين المحلي
    var box = await StorageService.openBox('settings_box');
    await box.put('is_dark_mode', !currentIsDark);
  }

  // ============================================================
  // 🟢 Getters مساعدة للتحقق من الصلاحيات بسرعة
  // ============================================================
  
  // هل المستخدم معلم؟
  bool get isTeacher => userData?['role'] == 'teacher';

  // هل المستخدم طالب؟
  bool get isStudent => userData?['role'] == 'student';

  // هل المستخدم مسجل دخول (سواء كعضو أو ضيف)؟
  bool get isLoggedIn => userData != null || isGuest;

  // ============================================================
  // 🔍 دوال التحقق من الملكية
  // ============================================================
  bool ownsCourse(String courseId) => myCourseIds.contains(courseId);
  bool ownsSubject(String subjectId) => mySubjectIds.contains(subjectId);

  // ============================================================
  // ⚙️ دوال إدارة الحالة (State Management)
  // ============================================================

  // ✅ تحديث بيانات المستخدم فقط (تستخدم بعد تسجيل الدخول أو تعديل البروفايل)
  void updateUserData(Map<String, dynamic> user) {
    userData = user;
    isGuest = false; // تأكيد أنه ليس ضيفاً
  }

  // ✅ ضبط حالة الضيف (تستخدم عند الدخول كزائر)
  void setGuest(bool value) {
    isGuest = value;
    if (value) {
      userData = null;
      myLibrary = [];
      myCourseIds = [];
      mySubjectIds = [];
    }
  }

  // تحديث البيانات القادمة من الـ API (Init Data)
  void updateFromInitData(Map<dynamic, dynamic> data) {
    // تحويل البيانات إلى Map<String, dynamic> لضمان التوافق
    final castedData = Map<String, dynamic>.from(data);

    // 1. استقبال كورسات المتجر (متاحة للجميع: مسجلين وضيوف)
    if (castedData['courses'] != null) {
      allCourses = (castedData['courses'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList();
    }
    
    // 2. بيانات المستخدم (إذا وجد في الرد، فهو ليس ضيفاً)
    if (castedData['user'] != null) {
      userData = Map<String, dynamic>.from(castedData['user']);
      isGuest = false; 
      
      // ✅ [تمت الإضافة] التأكد من وجود مفتاح الصورة في الـ userData
      // ملاحظة: الـ API يرسل 'profile_image' داخل كائن 'user' كما عدلناه سابقاً
    }

    // 3. أرقام الاشتراكات (فقط إذا لم يكن ضيفاً)
    if (!isGuest && castedData['myAccess'] != null) {
      myCourseIds = (castedData['myAccess']['courses'] as List?)
              ?.map((e) => e.toString())
              .toList() ?? [];

      mySubjectIds = (castedData['myAccess']['subjects'] as List?)
              ?.map((e) => e.toString())
              .toList() ?? [];
    }

    // 4. استقبال مكتبة الطالب الجاهزة
    if (!isGuest && castedData['library'] != null) {
      myLibrary = List<Map<String, dynamic>>.from(castedData['library']);
    } else {
      // إذا كان ضيفاً، نجعل المكتبة فارغة دائماً
      myLibrary = [];
    }
  }

  // ✅ محاولة تحميل البيانات من الذاكرة المحلية (Offline Mode)
  Future<bool> loadOfflineData() async {
    try {
      // فتح صندوق الكاش
      var cacheBox = await StorageService.openBox('app_cache');
      var authBox = await StorageService.openBox('auth_box');
      
      // جلب البيانات
      final cachedData = cacheBox.get('init_data');

      if (cachedData != null) {
        // تحديث التطبيق بالبيانات المخبأة
        updateFromInitData(cachedData);
        
        // ⚠️ استرجاع نوع المستخدم (role) وصورة البروفايل من auth_box لضمان التزامن
        if (userData != null) {
           if (authBox.containsKey('role')) {
             userData!['role'] = authBox.get('role');
           }
           // ✅ [تمت الإضافة] استرجاع الصورة محلياً لضمان ظهورها أوفلاين
           if (authBox.containsKey('profile_image')) {
             userData!['profile_image'] = authBox.get('profile_image');
           }
        }
        
        return true; // تم التحميل بنجاح
      }
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print("Offline Load Error: $e");
    }
    return false; // فشل التحميل أو لا توجد بيانات
  }

  // 🟢 دالة جديدة: تحديث بيانات التطبيق بالكامل من السيرفر
  // تستدعى عند: إضافة/تعديل/حذف كورس أو مادة
  Future<void> reloadAppInit() async {
    try {
      var box = await StorageService.openBox('auth_box');
      String? token = box.get('jwt_token');
      // ✅ 1. جلب معرف الجهاز
      String? deviceId = box.get('device_id'); 
      
      // التأكد من وجود التوكن قبل الطلب (للمستخدم المسجل فقط)
      if (token == null || isGuest) return;

      // ✅ التعديل هنا: إضافة timestamp لمنع الكاش وإجبار السيرفر على جلب بيانات جديدة
      final response = await Dio().get(
        'https://courses.aw478260.dpdns.org/api/public/get-app-init-data', 
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch, // 👈 هذا السطر يمنع الكاش
        },
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-device-id': deviceId, // ✅ 2. إرسال معرف الجهاز (بدونه يعتبرك السيرفر ضيفاً)
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );

      if (response.statusCode == 200) {
        updateFromInitData(response.data); // تحديث القوائم في الذاكرة
        
        // تحديث الكاش أيضاً لضمان التزامن
        var cacheBox = await StorageService.openBox('app_cache');
        await cacheBox.put('init_data', response.data);
        
        if (kDebugMode) print("✅ App Init Reloaded & Synced (Fresh Data)!");
      }
    } catch (e) {
      if (kDebugMode) print("❌ App Init Reload Error: $e");
    }
  }
  
  // دالة لمسح البيانات عند الخروج
  void clear() {
    userData = null;
    myCourseIds = [];
    mySubjectIds = [];
    myLibrary = [];
    isGuest = false; // إعادة تعيين حالة الضيف
    // لا نمسح allCourses لأنها بيانات عامة قد نحتاجها في صفحة الدخول
  }
}
