import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/course_model.dart';
import 'home_screen.dart'; // للعودة بعد الانتهاء

class ExamViewScreen extends StatefulWidget {
  final ExamModel exam;

  const ExamViewScreen({super.key, required this.exam});

  @override
  State<ExamViewScreen> createState() => _ExamViewScreenState();
}

class _ExamViewScreenState extends State<ExamViewScreen> {
  int currentIdx = 0;
  List<int?> userAnswers = [];
  bool isFinished = false;
  late int timeLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    userAnswers = List.filled(widget.exam.questions.length, null);
    timeLeft = widget.exam.durationMinutes * 60;
    _startTimer();
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
    for (int i = 0; i < widget.exam.questions.length; i++) {
      if (userAnswers[i] == widget.exam.questions[i].correctIndex) score++;
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    if (isFinished) {
      return _buildResultView();
    }

    final question = widget.exam.questions[currentIdx];
    final progress = (currentIdx + 1) / widget.exam.questions.length;

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
                          Text(
                            widget.exam.title.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "QUESTION ${currentIdx + 1} OF ${widget.exam.questions.length}",
                            style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: timeLeft < 60 ? AppColors.accentOrange.withOpacity(0.1) : AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: timeLeft < 60 ? AppColors.accentOrange : Colors.white.withOpacity(0.05),
                      ),
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
                    if (question.imageUrl != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          image: DecorationImage(
                            image: NetworkImage(question.imageUrl!),
                            fit: BoxFit.cover,
                          ),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                      ),
                    
                    Text(
                      question.text,
                      style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.2
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Options
                    ...List.generate(question.options.length, (index) {
                      final isSelected = userAnswers[currentIdx] == index;
                      return GestureDetector(
                        onTap: () => setState(() => userAnswers[currentIdx] = index),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.backgroundSecondary : AppColors.backgroundSecondary.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppColors.accentYellow : Colors.white.withOpacity(0.05),
                            ),
                            boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
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
                                        String.fromCharCode(65 + index),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: isSelected ? AppColors.backgroundPrimary : Colors.white24,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    question.options[index],
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
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

            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: currentIdx == 0 ? null : () => setState(() => currentIdx--),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: AppColors.textSecondary,
                        elevation: 0,
                        side: BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(LucideIcons.chevronLeft, size: 16),
                          SizedBox(width: 8),
                          Text("BACK"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (currentIdx == widget.exam.questions.length - 1) {
                          setState(() => isFinished = true);
                        } else {
                          setState(() => currentIdx++);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentIdx == widget.exam.questions.length - 1 
                            ? AppColors.accentOrange 
                            : AppColors.backgroundSecondary,
                        foregroundColor: currentIdx == widget.exam.questions.length - 1 
                            ? AppColors.backgroundPrimary 
                            : AppColors.accentYellow,
                        side: BorderSide(
                          color: currentIdx == widget.exam.questions.length - 1 
                              ? AppColors.accentOrange 
                              : AppColors.accentYellow.withOpacity(0.2)
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(currentIdx == widget.exam.questions.length - 1 ? "FINISH" : "NEXT"),
                          const SizedBox(width: 8),
                          Icon(
                            currentIdx == widget.exam.questions.length - 1 ? LucideIcons.checkCircle2 : LucideIcons.chevronRight, 
                            size: 16
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

  Widget _buildResultView() {
    final score = _calculateScore();
    final total = widget.exam.questions.length;
    final percentage = ((score / total) * 100).toInt();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Trophy Icon
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accentYellow.withOpacity(0.2)),
                  boxShadow: [BoxShadow(color: AppColors.accentYellow.withOpacity(0.2), blurRadius: 25)],
                ),
                child: const Icon(LucideIcons.trophy, size: 60, color: AppColors.accentYellow),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                "EXAM RESULTS",
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.0),
              ),
              const SizedBox(height: 8),
              Text(
                widget.exam.title.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentYellow.withOpacity(0.7), letterSpacing: 1.5),
              ),
              const SizedBox(height: 40),

              // Score Grid
              Row(
                children: [
                  Expanded(
                    child: _buildResultCard("SCORE", "$score / $total", AppColors.textPrimary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildResultCard("PERCENTAGE", "$percentage%", AppColors.accentYellow),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Return Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context, 
                    MaterialPageRoute(builder: (_) => const HomeScreen()), 
                    (r) => false
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  child: const Text("RETURN HOME"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textSecondary, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
