import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../../core/constants/app_colors.dart';
import 'exam_result_screen.dart';
import '../../core/services/storage_service.dart';

class ExamViewScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final bool isCompleted;
  // ✅ تم حذف durationMinutes من هنا لأننا سنجلبه من الـ API مباشرة

  const ExamViewScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.isCompleted,
  });

  @override
  State<ExamViewScreen> createState() => _ExamViewScreenState();
}

class _ExamViewScreenState extends State<ExamViewScreen> {
  bool _loading = true;
  List<dynamic> _questions = [];
  
  // متغير لتحديد ما إذا كنا في وضع "نموذج الإجابة"
  bool _isModelAnswerMode = false;

  int currentIdx = 0;
  Map<String, int> userAnswers = {}; 
  int timeLeft = 0;
  Timer? _timer;
  String? _attemptId;
  
  String? _userId;
  String? _deviceId;
  String? _token; 
  final String _appSecret = const String.fromEnvironment('APP_SECRET');

  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Opened Exam: ${widget.examId}");
    _startExamAttempt();
  }

  Future<void> _startExamAttempt() async {
    try {
      var box = await StorageService.openBox('auth_box');
      _userId = box.get('user_id');
      _deviceId = box.get('device_id');
      _token = box.get('jwt_token');
      final name = box.get('first_name') ?? 'Student';

      final res = await Dio().post(
        '$_baseUrl/api/exams/start-attempt',
        data: {'examId': widget.examId, 'studentName': name},
        options: Options(headers: {
          'Authorization': 'Bearer $_token',
          'x-device-id': _deviceId,
          'x-app-secret': _appSecret,
        }),
      );

      if (mounted && res.statusCode == 200) {
        final data = res.data;
        
        // ✅ 1. التحقق من وضع نموذج الإجابة (إذا انتهى الوقت)
        if (data['mode'] == 'model_answer') {
           setState(() {
             _isModelAnswerMode = true; // تفعيل وضع العرض فقط
             _questions = data['questions'] ?? [];
             timeLeft = 0; // لا يوجد وقت
             _loading = false;
           });
           // ⚠️ لا نبدأ المؤقت في هذا الوضع
        } else {
           // الوضع الطبيعي (بدء امتحان)
           // ✅ 2. جلب التوقيت الصحيح من الـ API
           int apiDuration = data['durationMinutes'] ?? 30; // القيمة الافتراضية 30 إذا لم تأتِ

           setState(() {
             _isModelAnswerMode = false;
             _questions = data['questions'] ?? [];
             _attemptId = data['attemptId'].toString();
             timeLeft = apiDuration * 60; // تحويل الدقائق لثواني
             _loading = false;
           });
           _startTimer();
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Start Exam Failed');
      if (mounted) {
        String msg = "Failed to start exam";
        if (e is DioException) {
           if (e.response?.statusCode == 403) msg = e.response?.data['error'] ?? "Access Denied";
           if (e.response?.statusCode == 409) msg = "Exam already completed";
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft <= 0) {
        timer.cancel();
        _submitExam(autoSubmit: true);
      } else {
        setState(() => timeLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return "0:00";
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    // ⚠️ في وضع نموذج الإجابة، هذا الزر يعمل كزر خروج فقط
    if (_isModelAnswerMode) {
      Navigator.pop(context);
      return;
    }

    _timer?.cancel();
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
    );

    try {
      Map<String, int> finalAnswers = {};
      userAnswers.forEach((k, v) => finalAnswers[k] = v);

      await Dio().post(
        '$_baseUrl/api/exams/submit-attempt',
        data: {'attemptId': _attemptId, 'answers': finalAnswers},
        options: Options(headers: {
          'Authorization': 'Bearer $_token',
          'x-device-id': _deviceId,
          'x-app-secret': _appSecret,
        }),
      );

      if (mounted) {
        Navigator.pop(context); 
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
                attemptId: _attemptId!, 
                examTitle: widget.examTitle
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to submit. Try again."), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));

    final questionData = _questions[currentIdx];
    final String questionId = questionData['id'].toString();
    final String? imageFileId = questionData['image_file_id'];
    final options = (questionData['options'] as List).cast<Map<String, dynamic>>();
    final progress = (currentIdx + 1) / _questions.length;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header & Timer
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Q ${currentIdx + 1}/${_questions.length}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                  
                  // ✅ إخفاء المؤقت أو تغييره في وضع نموذج الإجابة
                  if (!_isModelAnswerMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: timeLeft < 60 ? AppColors.error.withOpacity(0.2) : AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: timeLeft < 60 ? AppColors.error : Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.clock, size: 14, color: timeLeft < 60 ? AppColors.error : AppColors.accentYellow),
                          const SizedBox(width: 6),
                          Text(_formatTime(timeLeft), style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: timeLeft < 60 ? AppColors.error : Colors.white)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.accentYellow.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                      child: const Text("MODEL ANSWER", style: TextStyle(color: AppColors.accentYellow, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            
            LinearProgressIndicator(value: progress, backgroundColor: AppColors.backgroundSecondary, color: AppColors.accentYellow, minHeight: 4),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageFileId != null && imageFileId.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        constraints: const BoxConstraints(maxHeight: 250),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: '$_baseUrl/api/exams/get-image?file_id=$imageFileId',
                            httpHeaders: {
                              'Authorization': 'Bearer $_token',
                              'x-device-id': _deviceId ?? '',
                              'x-app-secret': _appSecret,
                            },
                            placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
                            errorWidget: (context, url, error) => const Icon(Icons.error, color: AppColors.error),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    
                    Text(
                      questionData['question_text'] ?? "Question Text",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.4),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // الخيارات
                    ...options.map((opt) {
                      final int optId = opt['id'];
                      
                      // ✅ منطق الألوان الجديد
                      bool isSelected = false;
                      bool isCorrectModel = false;

                      if (_isModelAnswerMode) {
                        // في وضع الإجابة النموذجية، نلون الإجابة الصحيحة بالأخضر
                        isCorrectModel = opt['is_correct'] == true;
                      } else {
                        // في الوضع العادي، نلون ما اختاره الطالب
                        isSelected = userAnswers[questionId] == optId;
                      }
                      
                      // تحديد الألوان بناءً على الوضع
                      Color bgColor = AppColors.backgroundSecondary;
                      Color borderColor = Colors.white.withOpacity(0.05);

                      if (_isModelAnswerMode && isCorrectModel) {
                         bgColor = AppColors.success.withOpacity(0.2); // خلفية خضراء للصحيح
                         borderColor = AppColors.success;
                      } else if (isSelected) {
                         bgColor = AppColors.accentYellow.withOpacity(0.1);
                         borderColor = AppColors.accentYellow;
                      }
                      
                      return GestureDetector(
                        onTap: () {
                          // ⛔ منع التعديل في وضع نموذج الإجابة
                          if (_isModelAnswerMode) return;
                          setState(() => userAnswers[questionId] = optId);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: borderColor,
                              width: (isSelected || isCorrectModel) ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24, height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (isSelected || isCorrectModel) 
                                        ? (_isModelAnswerMode && isCorrectModel ? AppColors.success : AppColors.accentYellow) 
                                        : Colors.white24, 
                                    width: 2
                                  ),
                                  color: (isSelected || isCorrectModel) 
                                      ? (_isModelAnswerMode && isCorrectModel ? AppColors.success : AppColors.accentYellow) 
                                      : Colors.transparent,
                                ),
                                child: (isSelected || isCorrectModel) 
                                    ? const Icon(Icons.check, size: 16, color: AppColors.backgroundPrimary) 
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  opt['option_text'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: (isSelected || isCorrectModel) ? FontWeight.bold : FontWeight.normal,
                                    color: (isSelected || isCorrectModel) ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            
            // أزرار التنقل
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
              child: Row(
                children: [
                  if (currentIdx > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => currentIdx--),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.white10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text("BACK", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (currentIdx > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (currentIdx == _questions.length - 1) {
                           // إذا كان نموذج إجابة، فالزر يغلق الشاشة، وإلا يرسل الامتحان
                           if (_isModelAnswerMode) {
                             Navigator.pop(context);
                           } else {
                             _submitExam();
                           }
                        } else {
                          setState(() => currentIdx++);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isModelAnswerMode ? Colors.grey[800] : AppColors.accentYellow, 
                        foregroundColor: _isModelAnswerMode ? Colors.white : AppColors.backgroundPrimary, 
                        padding: const EdgeInsets.symmetric(vertical: 16), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: Text(
                        currentIdx == _questions.length - 1 
                            ? (_isModelAnswerMode ? "CLOSE" : "FINISH") // ✅ تغيير النص حسب الوضع
                            : "NEXT", 
                        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
