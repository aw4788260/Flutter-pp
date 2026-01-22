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
      
      // جلب البيانات
      final cachedData = cacheBox.get('init_data');

      if (cachedData != null) {
        // تحديث التطبيق بالبيانات المخبأة
        updateFromInitData(cachedData);
        
        // ⚠️ مهم: استرجاع نوع المستخدم (role) المخزن في auth_box لضمان تزامن الصلاحيات
        // لأن init_data قد لا تحتوي دائماً على الـ role بشكل صريح في بعض الحالات
        var authBox = await StorageService.openBox('auth_box');
        if (userData != null && authBox.containsKey('role')) {
           userData!['role'] = authBox.get('role');
        }
        
        return true; // تم التحميل بنجاح
      }
    } catch (e) {
      // ignore: avoid_print
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
    isGuest = false; // إعادة تعيين حالة الضيف
    // لا نمسح allCourses لأنها بيانات عامة قد نحتاجها في صفحة الدخول
  }
}
