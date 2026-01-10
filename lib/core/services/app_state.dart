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

  // التحقق من الملكية
  bool ownsCourse(String courseId) => myCourseIds.contains(courseId);
  bool ownsSubject(String subjectId) => mySubjectIds.contains(subjectId);

  // تحديث البيانات القادمة من الـ API
  void updateFromInitData(Map<String, dynamic> data) {
    // 1. استقبال كورسات المتجر
    if (data['courses'] != null) {
      allCourses = (data['courses'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList();
    }
    
    // 2. بيانات المستخدم
    if (data['user'] != null) {
      userData = data['user'];
    }

    // 3. أرقام الاشتراكات (للحماية والتحقق الداخلي)
    if (data['myAccess'] != null) {
      myCourseIds = (data['myAccess']['courses'] as List?)
              ?.map((e) => e.toString())
              .toList() ?? [];

      mySubjectIds = (data['myAccess']['subjects'] as List?)
              ?.map((e) => e.toString())
              .toList() ?? [];
    }

    // 4. ✅ استقبال مكتبة الطالب الجاهزة (نصوص)
    if (data['library'] != null) {
      myLibrary = List<Map<String, dynamic>>.from(data['library']);
    }
  }
  
  // دالة لمسح البيانات عند الخروج
  void clear() {
    userData = null;
    myCourseIds = [];
    mySubjectIds = [];
    myLibrary = [];
    // لا نمسح allCourses لأنها بيانات عامة
  }
}
