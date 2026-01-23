import 'dart:io';
import 'package:dio/dio.dart';
import '../services/storage_service.dart';

class TeacherService {
  final Dio _dio = Dio();
  // ⚠️ تأكد من أن هذا الرابط صحيح ويعمل
  final String baseUrl = "https://courses.aw478260.dpdns.org/api";
  
  // يفضل تعريف Secret التطبيق هنا أو جلبه من البيئة لضمان المرور من حماية السيرفر
  final String _appSecret = const String.fromEnvironment('APP_SECRET');

  // 🔒 دالة تجهيز الهيدر (Token + Device ID + App Secret)
  Future<Options> _getHeaders({bool isUpload = false}) async {
    var box = await StorageService.openBox('auth_box');
    String? token = box.get('jwt_token');
    String? deviceId = box.get('device_id');

    final Map<String, dynamic> headers = {
      'Authorization': 'Bearer $token',
      'x-device-id': deviceId,
      'x-app-secret': _appSecret, 
    };

    if (!isUpload) {
      headers['Content-Type'] = 'application/json';
    }

    return Options(headers: headers);
  }

  // ==========================================================
  // 1️⃣ إدارة المحتوى (إضافة - تعديل - حذف)
  // ==========================================================
  Future<dynamic> manageContent({
    required String action, // 'create', 'update', 'delete'
    required String type,   // 'courses', 'subjects', 'chapters', 'videos', 'pdfs'
    required Map<String, dynamic> data,
  }) async {
    try {
      final options = await _getHeaders();
      final response = await _dio.post(
        '$baseUrl/teacher/content',
        data: {
          'action': action,
          'type': type,
          'data': data
        },
        options: options,
      );
      return response.data;
    } catch (e) {
      if (e is DioException) {
         throw Exception(e.response?.data['error'] ?? "حدث خطأ في الاتصال بالسيرفر");
      }
      throw Exception("فشل تنفيذ العملية: $e");
    }
  }

  // ==========================================================
  // 2️⃣ رفع الملفات
  // ==========================================================
  Future<String> uploadFile(File file, {Function(int sent, int total)? onProgress}) async {
    try {
      final options = await _getHeaders(isUpload: true);
      String fileName = file.path.split('/').last;
      
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _dio.post(
        '$baseUrl/teacher/upload',
        data: formData,
        options: options,
        onSendProgress: (sent, total) {
          if (onProgress != null && total != -1) {
            onProgress(sent, total);
          }
        },
      );
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['url'];
      } else {
        throw Exception("فشل رفع الملف");
      }
    } catch (e) {
      throw Exception("خطأ أثناء الرفع: $e");
    }
  }

  // ==========================================================
  // 3️⃣ إدارة الطلبات والطلاب
  // ==========================================================
  
  // جلب الطلبات المعلقة
  Future<List<dynamic>> getPendingRequests() async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/students',
      queryParameters: {'mode': 'requests'},
      options: options,
    );
    return response.data;
  }

  // قبول أو رفض طلب اشتراك
  Future<void> handleRequest(String requestId, bool approve, {String? reason}) async {
    final options = await _getHeaders();
    await _dio.post(
      '$baseUrl/teacher/students',
      data: {
        'action': 'handle_request',
        'payload': {
          'requestId': requestId,
          'decision': approve ? 'approve' : 'reject',
          'rejectionReason': reason
        }
      },
      options: options,
    );
  }

  // البحث عن طالب
  Future<Map<String, dynamic>> searchStudent(String query) async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/students',
      queryParameters: {'mode': 'search', 'query': query},
      options: options,
    );
    return response.data;
  }

  // منح أو سحب صلاحية
  Future<void> toggleAccess(String studentId, String type, String itemId, bool allow) async {
    final options = await _getHeaders();
    await _dio.post(
      '$baseUrl/teacher/students',
      data: {
        'action': 'manage_access',
        'payload': {
          'studentId': studentId,
          'type': type, 
          'itemId': itemId,
          'allow': allow
        }
      },
      options: options,
    );
  }

  // جلب محتوى المعلم
  Future<List<dynamic>> getMyContent() async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/students',
      queryParameters: {'mode': 'my_content'},
      options: options,
    );
    return response.data;
  }

  // ==========================================================
  // 4️⃣ إدارة فريق العمل
  // ==========================================================
  
  // جلب أعضاء الفريق
  Future<List<dynamic>> getTeamMembers() async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/team',
      queryParameters: {'mode': 'list'},
      options: options,
    );
    return response.data;
  }

  // البحث عن طلاب لترقيتهم
  Future<List<dynamic>> searchStudentsForTeam(String query) async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/team',
      queryParameters: {'mode': 'search', 'query': query},
      options: options,
    );
    return response.data;
  }

  // إدارة العضو
  Future<void> manageTeamMember({required String action, required String userId}) async {
    final options = await _getHeaders();
    await _dio.post(
      '$baseUrl/teacher/team',
      data: {
        'action': action, // 'promote' or 'demote'
        'userId': userId,
      },
      options: options,
    );
  }

  // ==========================================================
  // 5️⃣ الامتحانات (إنشاء - تعديل - حذف - إحصائيات)
  // ==========================================================
  
  // إنشاء أو تحديث امتحان
  Future<void> createExam(Map<String, dynamic> examData) async {
    final options = await _getHeaders();
    
    // تحديد نوع العملية بناءً على وجود المعرف
    String action = examData.containsKey('examId') ? 'update' : 'create';

    await _dio.post(
      '$baseUrl/teacher/exams',
      data: {
        'action': action,
        'payload': examData
      },
      options: options,
    );
  }

  // ✅ حذف امتحان
  Future<void> deleteExam(String examId) async {
    final options = await _getHeaders();
    
    await _dio.post(
      '$baseUrl/teacher/exams',
      data: {
        'action': 'delete',
        'payload': {'examId': examId}
      },
      options: options,
    );
  }

  // جلب تفاصيل الامتحان للمعلم (لغرض التعديل)
  Future<Map<String, dynamic>> getExamDetails(String examId) async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/get-exam-details',
      queryParameters: {'examId': examId},
      options: options,
    );
    return response.data;
  }

  // جلب إحصائيات امتحان معين
  Future<Map<String, dynamic>> getExamStats(String examId) async {
    final options = await _getHeaders();
    final response = await _dio.get(
      '$baseUrl/teacher/exams',
      queryParameters: {'examId': examId},
      options: options,
    );
    return response.data;
  }

  // ==========================================================
  // 6️⃣ الإحصائيات المالية (NEW)
  // ==========================================================
  
  // جلب الإحصائيات المالية والطلاب
  Future<Map<String, dynamic>> getFinancialStats() async {
    try {
      final options = await _getHeaders();
      final response = await _dio.get(
        '$baseUrl/teacher/financial-stats',
        options: options,
      );
      return response.data;
    } catch (e) {
      if (e is DioException) {
         throw Exception(e.response?.data['error'] ?? "فشل جلب الإحصائيات المالية");
      }
      throw Exception('فشل جلب الإحصائيات المالية: $e');
    }
  }
}
