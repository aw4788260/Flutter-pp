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

  // ✅ 1. متغير لتحديد هل المستخدم ضيف أم لا
  bool isGuest = false;

  // getter للتحقق من تسجيل الدخول بسرعة
  // ✅ التعديل: السماح بالدخول إذا كان المستخدم مسجلاً أو زائراً
  bool get isLoggedIn => userData != null || isGuest;

  // التحقق من الملكية
  bool ownsCourse(String courseId) => myCourseIds.contains(courseId);
  bool ownsSubject(String subjectId) => mySubjectIds.contains(subjectId);

  // تحديث البيانات القادمة من الـ API
  void updateFromInitData(Map<dynamic, dynamic> data) {
    // تحويل البيانات إلى Map<String, dynamic> لضمان التوافق
    final castedData = Map<String, dynamic>.from(data);

    // 1. استقبال كورسات المتجر (متاحة للجميع: مسجلين وضيوف)
    if (castedData['courses'] != null) {
      allCourses = (castedData['courses'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList();
    }
    
    // 2. بيانات المستخدم (فقط إذا لم يكن ضيفاً)
    if (!isGuest && castedData['user'] != null) {
      userData = Map<String, dynamic>.from(castedData['user']);
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

    // 4. ✅ استقبال مكتبة الطالب الجاهزة
    if (!isGuest && castedData['library'] != null) {
      myLibrary = List<Map<String, dynamic>>.from(castedData['library']);
    } else {
      // ✅ إذا كان ضيفاً، نجعل المكتبة فارغة دائماً
      myLibrary = [];
    }
  }

  // ✅ دالة: محاولة تحميل البيانات من الذاكرة المحلية (Offline Mode)
  Future<bool> loadOfflineData() async {
    try {
      // فتح صندوق الكاش
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
    isGuest = false; // ✅ إعادة تعيين حالة الضيف
    // لا نمسح allCourses لأنها بيانات عامة قد نحتاجها في صفحة الدخول
  }
}
