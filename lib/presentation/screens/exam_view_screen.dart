import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'exam_result_screen.dart'; // ✅ استيراد شاشة النتيجة الجديدة

class ExamViewScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final bool isCompleted;

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
  // حالة البيانات
  bool _loading = true;
  List<dynamic> _questions = [];
  
  // حالة الامتحان
  int currentIdx = 0;
  List<int?> userAnswers = []; // يخزن index الإجابة المختارة
  bool isFinished = false;
  int timeLeft = 0;
  Timer? _timer;
  
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    _fetchExamDetails();
  }

  // --- 1. جلب الأسئلة من السيرفر ---
  Future<void> _fetchExamDetails() async {
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      
      // استدعاء API جلب الأسئلة
      final res = await Dio().get(
        '$_baseUrl/api/student/get-exam-questions',
        queryParameters: {'examId': widget.examId},
        options: Options(headers: {
    'x-user-id': userId,
    'x-app-secret': const String.fromEnvironment('APP_SECRET'), // ✅ إضافة مباشرة
  }),
      );

      if (mounted && res.statusCode == 200) {
        final data = res.data;
        setState(() {
          _questions = data['questions'] ?? [];
          // المدة بالدقائق من السيرفر، أو افتراضياً 30 دقيقة
          int durationMinutes = data['duration'] ?? 30;
          timeLeft = durationMinutes * 60;
          
          // تهيئة مصفوفة الإجابات بـ null
          userAnswers = List.filled(_questions.length, null);
          _loading = false;
        });
        _startTimer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load exam"), backgroundColor: AppColors.error));
        Navigator.pop(context);
      }
    }
  }

  // --- 2. المؤقت ---
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft <= 0) {
        timer.cancel();
        _submitExam(); // إنهاء تلقائي عند نفاذ الوقت
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
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  // --- 3. حساب النتيجة وإنهاء الامتحان ---
  void _submitExam() {
    _timer?.cancel();
    setState(() => isFinished = true);
    // هنا يمكنك إضافة كود لإرسال الإجابات للسيرفر لحفظها (POST Request)
  }

  int _calculateScore() {
    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      // نفترض أن الـ API يرسل رقم الإجابة الصحيحة في الحقل 'correct_option_index' (0, 1, 2, 3)
      // تأكد من مطابقة هذا الاسم مع ما يرسله الباك اند لديك
      final correctIdx = _questions[i]['correct_option_index']; 
      
      // مقارنة إجابة المستخدم بالإجابة الصحيحة
      if (userAnswers[i] != null && userAnswers[i] == correctIdx) {
        score++;
      }
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    // شاشة التحميل
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
      );
    }

    // شاشة النتيجة (عند الانتهاء)
    if (isFinished) {
      final score = _calculateScore();
      final total = _questions.length;
      final wrong = total - score;

      return ExamResultScreen(
        examTitle: widget.examTitle,
        score: score,
        totalQuestions: total,
        correctAnswers: score,
        wrongAnswers: wrong,
      );
    }

    // شاشة الأسئلة (الامتحان الجاري)
    final questionData = _questions[currentIdx];
    final questionText = questionData['question_text'] ?? "No question text";
    final imageUrl = questionData['image_url']; // يمكن أن يكون null
    final options = (questionData['options'] as List? ?? []).cast<String>();
    
    final progress = (currentIdx + 1) / _questions.length;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // تأكيد الخروج قبل إنهاء الامتحان
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.backgroundSecondary,
                              title: const Text("Exit Exam?", style: TextStyle(color: Colors.white)),
                              content: const Text("Your progress will be lost.", style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                                TextButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text("Exit", style: TextStyle(color: AppColors.error))),
                              ],
                            ),
                          );
                        },
                        child: const Icon(LucideIcons.x, color: AppColors.textSecondary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.examTitle.toUpperCase(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "QUESTION ${currentIdx + 1} OF ${_questions.length}",
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Timer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: timeLeft < 60 ? AppColors.accentOrange.withOpacity(0.1) : AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: timeLeft < 60 ? AppColors.accentOrange : Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.clock, size: 16, color: timeLeft < 60 ? AppColors.accentOrange : AppColors.accentYellow),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(timeLeft),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: timeLeft < 60 ? AppColors.accentOrange : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Progress Bar
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.backgroundSecondary,
              color: AppColors.accentYellow,
              minHeight: 4,
            ),
            
            // Question Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // صورة السؤال (إن وجدت)
                    if (imageUrl != null && imageUrl.toString().isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          image: DecorationImage(
                            image: NetworkImage(imageUrl),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    
                    // نص السؤال
                    Text(
                      questionText,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // الخيارات
                    ...List.generate(options.length, (index) {
                      final isSelected = userAnswers[currentIdx] == index;
                      
                      return GestureDetector(
                        onTap: () => setState(() => userAnswers[currentIdx] = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.backgroundSecondary : AppColors.backgroundSecondary.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppColors.accentYellow : Colors.white.withOpacity(0.05),
                              width: isSelected ? 1.5 : 1,
                            ),
                            boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    // Option Letter (A, B, C, D)
                                    Container(
                                      width: 32, height: 32,
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppColors.accentYellow : Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? AppColors.accentYellow : Colors.white.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          String.fromCharCode(65 + index), // A, B, C...
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isSelected ? AppColors.backgroundPrimary : Colors.white24,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Option Text
                                    Expanded(
                                      child: Text(
                                        options[index],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected) 
                                const Icon(LucideIcons.checkCircle2, color: AppColors.accentYellow, size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            
            // Bottom Navigation (Back / Next)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  // Back Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: currentIdx == 0 
                          ? null 
                          : () => setState(() => currentIdx--),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: AppColors.textSecondary,
                        elevation: 0,
                        side: BorderSide(color: Colors.white.withOpacity(0.05)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(LucideIcons.chevronLeft, size: 16),
                          SizedBox(width: 8),
                          Text("BACK", style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Next / Finish Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (currentIdx == _questions.length - 1) {
                          _submitExam();
                        } else {
                          setState(() => currentIdx++);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentIdx == _questions.length - 1 
                            ? AppColors.accentOrange 
                            : AppColors.backgroundSecondary,
                        foregroundColor: currentIdx == _questions.length - 1 
                            ? AppColors.backgroundPrimary 
                            : AppColors.accentYellow,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        side: BorderSide(
                          color: currentIdx == _questions.length - 1 
                              ? AppColors.accentOrange 
                              : AppColors.accentYellow.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentIdx == _questions.length - 1 ? "FINISH" : "NEXT",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            currentIdx == _questions.length - 1 ? LucideIcons.checkCircle2 : LucideIcons.chevronRight, 
                            size: 16,
                          ),
                        ],
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
