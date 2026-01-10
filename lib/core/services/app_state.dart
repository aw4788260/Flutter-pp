import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/course_model.dart';

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

  // getter للتحقق من تسجيل الدخول بسرعة
  bool get isLoggedIn => userData != null;

  // التحقق من الملكية
  bool ownsCourse(String courseId) => myCourseIds.contains(courseId);
  bool ownsSubject(String subjectId) => mySubjectIds.contains(subjectId);

  // تحديث البيانات القادمة من الـ API
  void updateFromInitData(Map<dynamic, dynamic> data) {
    // تحويل البيانات إلى Map<String, dynamic> لضمان التوافق
    final castedData = Map<String, dynamic>.from(data);

    // 1. استقبال كورسات المتجر
    if (castedData['courses'] != null) {
      allCourses = (castedData['courses'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList();
    }
    
    // 2. بيانات المستخدم
    if (castedData['user'] != null) {
      userData = Map<String, dynamic>.from(castedData['user']);
    }

    // 3. أرقام الاشتراكات (للحماية والتحقق الداخلي)
    if (castedData['myAccess'] != null) {
      myCourseIds = (castedData['myAccess']['courses'] as List?)
              ?.map((e) => e.toString())
              .toList() ?? [];

      mySubjectIds = (castedData['myAccess']['subjects'] as List?)
              ?.map((e) => e.toString())
              .toList() ?? [];
    }

    // 4. ✅ استقبال مكتبة الطالب الجاهزة
    if (castedData['library'] != null) {
      myLibrary = List<Map<String, dynamic>>.from(castedData['library']);
    }
  }

  // ✅ دالة جديدة: محاولة تحميل البيانات من الذاكرة المحلية (Offline Mode)
  Future<bool> loadOfflineData() async {
    try {
      // فتح صندوق الكاش (تأكد من استخدام نفس الاسم الموجود في Splash Screen)
      var cacheBox = await Hive.openBox('app_cache');
      
      // جلب البيانات
      final cachedData = cacheBox.get('init_data');

      if (cachedData != null) {
        // إذا وجدت بيانات، قم بتحديث التطبيق بها
        updateFromInitData(cachedData);
        return true; // تم التحميل بنجاح
      }
    } catch (e) {
      print("Offline Load Error: $e");
    }
    return false; // فشل التحميل أو لا توجد بيانات
  }
  
  // دالة لمسح البيانات عند الخروج
  void clear() {
    userData = null;
    myCourseIds = [];
    mySubjectIds = [];
    myLibrary = [];
    // لا نمسح allCourses لأنها بيانات عامة قد نحتاجها في صفحة الدخول
  }
}
