import '../../data/models/course_model.dart';

class AppState {
  // Singleton Pattern
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // البيانات المخزنة
  List<CourseModel> allCourses = [];
  Map<String, dynamic>? userData;
  List<String> myCourseIds = [];
  List<String> mySubjectIds = [];

  // التحقق من الملكية
  bool ownsCourse(String courseId) => myCourseIds.contains(courseId);
  bool ownsSubject(String subjectId) => mySubjectIds.contains(subjectId);

  // تحديث البيانات القادمة من الـ API
  void updateFromInitData(Map<String, dynamic> data) {
    if (data['courses'] != null) {
      allCourses = (data['courses'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList();
    }
    
    if (data['user'] != null) {
      userData = data['user'];
    }

    if (data['myAccess'] != null) {
      myCourseIds = List<String>.from(data['myAccess']['courses'] ?? []);
      mySubjectIds = List<String>.from(data['myAccess']['subjects'] ?? []);
    }
  }
  
  // دالة لمسح البيانات عند الخروج
  void clear() {
    userData = null;
    myCourseIds = [];
    mySubjectIds = [];
    // لا نمسح الكورسات لأنها عامة
  }
}
