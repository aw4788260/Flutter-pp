import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'main_wrapper.dart'; // للعودة للرئيسية

class ExamViewScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final bool isCompleted;

  // نستقبل المعرفات بدلاً من الموديل الكامل
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
  // حالة التحميل والبيانات
  bool _loading = true;
  List<dynamic> _questions = [];
  int _durationMinutes = 0;
  
  // حالة الامتحان النشط
  int currentIdx = 0;
  List<int?> userAnswers = [];
  bool isFinished = false;
  int timeLeft = 0;
  Timer? _timer;
  
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    _fetchExamDetails();
  }

  Future<void> _fetchExamDetails() async {
    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');
      
      // جلب الأسئلة من API (سنفترض وجود API لهذا الغرض أو نستخدم API المحتوى)
      // للتبسيط، سنفترض أن API get-subject-content يرسل الأسئلة، 
      // أو سنستخدم API مخصص (get-exam-questions).
      // هنا سأكتب الكود لطلب API مخصص للامتحان.
      
      final res = await Dio().get(
        '$_baseUrl/api/student/get-exam-questions', // تأكد من إنشاء هذا الـ API في الباك اند
        queryParameters: {'examId': widget.examId},
        options: Options(headers: {'x-user-id': userId}),
      );

      if (mounted && res.statusCode == 200) {
        final data = res.data;
        setState(() {
          _questions = data['questions'] ?? [];
          _durationMinutes = data['duration'] ?? 30;
          timeLeft = _durationMinutes * 60;
          userAnswers = List.filled(_questions.length, null);
          _loading = false;
        });
        _startTimer();
      }
    } catch (e) {
      if (mounted) {
        // في حالة الخطأ أو عدم وجود API، سنعرض رسالة خطأ
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load exam"), backgroundColor: AppColors.error));
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft <= 0) {
        timer.cancel();
        setState(() => isFinished = true);
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

  int _calculateScore() {
    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      // نفترض أن الـ API يعيد index الإجابة الصحيحة في 'correct_option_index'
      // أو يمكن أن يعيد الإجابة نفسها ونقارن النصوص
      final correctIdx = _questions[i]['correct_option_index'] as int; 
      if (userAnswers[i] == correctIdx) score++;
    }
    return score;
  }

  // إرسال النتيجة للسيرفر (اختياري)
  Future<void> _submitExam() async {
    // كود إرسال النتيجة...
    setState(() => isFinished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    
    if (isFinished) return _buildResultView();

    final question = _questions[currentIdx];
    final options = (question['options'] as List).cast<String>();
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
                        onTap: () => Navigator.pop(context),
                        child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.examTitle.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text("QUESTION ${currentIdx + 1} OF ${_questions.length}", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: timeLeft < 60 ? AppColors.accentOrange.withOpacity(0.1) : AppColors.backgroundSecondary, 
                      borderRadius: BorderRadius.circular(50), 
                      border: Border.all(color: timeLeft < 60 ? AppColors.accentOrange : Colors.white.withOpacity(0.05))
                    ),
                    child: Row(children: [
                      Icon(LucideIcons.clock, size: 16, color: timeLeft < 60 ? AppColors.accentOrange : AppColors.accentYellow), 
                      const SizedBox(width: 8), 
                      Text(_formatTime(timeLeft), style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: timeLeft < 60 ? AppColors.accentOrange : AppColors.textPrimary))
                    ]),
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
                    if (question['image_url'] != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24), 
                        height: 200, 
                        width: double.infinity, 
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20), 
                          image: DecorationImage(image: NetworkImage(question['image_url']), fit: BoxFit.cover), 
                          border: Border.all(color: Colors.white.withOpacity(0.1))
                        )
                      ),
                    
                    Text(
                      question['question_text'], 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.2)
                    ),
                    
                    const SizedBox(height: 32),
                    
                    ...List.generate(options.length, (index) {
                      final isSelected = userAnswers[currentIdx] == index;
                      return GestureDetector(
                        onTap: () => setState(() => userAnswers[currentIdx] = index),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12), 
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.backgroundSecondary : AppColors.backgroundSecondary.withOpacity(0.5), 
                            borderRadius: BorderRadius.circular(16), 
                            border: Border.all(color: isSelected ? AppColors.accentYellow : Colors.white.withOpacity(0.05)), 
                            boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : []
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                            children: [
                              Row(children: [
                                Container(
                                  width: 32, height: 32, 
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.accentYellow : Colors.transparent, 
                                    shape: BoxShape.circle, 
                                    border: Border.all(color: isSelected ? AppColors.accentYellow : Colors.white.withOpacity(0.2))
                                  ), 
                                  child: Center(child: Text(String.fromCharCode(65 + index), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? AppColors.backgroundPrimary : Colors.white24)))
                                ), 
                                const SizedBox(width: 16), 
                                Text(options[index], style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary))
                              ]), 
                              if (isSelected) const Icon(LucideIcons.checkCircle2, color: AppColors.accentYellow, size: 20)
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
              child: Row(
                children: [
                  Expanded(child: ElevatedButton(onPressed: currentIdx == 0 ? null : () => setState(() => currentIdx--), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppColors.textSecondary, elevation: 0, side: BorderSide(color: Colors.white.withOpacity(0.05))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(LucideIcons.chevronLeft, size: 16), SizedBox(width: 8), Text("BACK")]))),
                  const SizedBox(width: 16),
                  Expanded(child: ElevatedButton(onPressed: () { if (currentIdx == _questions.length - 1) { _submitExam(); } else { setState(() => currentIdx++); } }, style: ElevatedButton.styleFrom(backgroundColor: currentIdx == _questions.length - 1 ? AppColors.accentOrange : AppColors.backgroundSecondary, foregroundColor: currentIdx == _questions.length - 1 ? AppColors.backgroundPrimary : AppColors.accentYellow, side: BorderSide(color: currentIdx == _questions.length - 1 ? AppColors.accentOrange : AppColors.accentYellow.withOpacity(0.2))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(currentIdx == _questions.length - 1 ? "FINISH" : "NEXT"), const SizedBox(width: 8), Icon(currentIdx == _questions.length - 1 ? LucideIcons.checkCircle2 : LucideIcons.chevronRight, size: 16)]))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView() {
    final score = _calculateScore();
    final total = _questions.length;
    final percentage = total > 0 ? ((score / total) * 100).toInt() : 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 120, height: 120, decoration: BoxDecoration(color: AppColors.backgroundSecondary, shape: BoxShape.circle, border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)), boxShadow: [BoxShadow(color: AppColors.accentYellow.withOpacity(0.2), blurRadius: 25)]), child: const Icon(LucideIcons.trophy, size: 60, color: AppColors.accentYellow)),
              const SizedBox(height: 32),
              const Text("EXAM RESULTS", style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.0)),
              const SizedBox(height: 8),
              Text(widget.examTitle.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentYellow.withOpacity(0.7), letterSpacing: 1.5)),
              const SizedBox(height: 40),
              Row(children: [Expanded(child: _buildResultCard("SCORE", "$score / $total", AppColors.textPrimary)), const SizedBox(width: 16), Expanded(child: _buildResultCard("PERCENTAGE", "$percentage%", AppColors.accentYellow))]),
              const SizedBox(height: 40),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainWrapper()), (r) => false), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)), child: const Text("RETURN HOME"))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(String label, String value, Color color) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.backgroundSecondary, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textSecondary, letterSpacing: 1.5)), const SizedBox(height: 8), Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color))]));
  }
}
