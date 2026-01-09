import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:percent_indicator/percent_indicator.dart'; // تأكد من إضافة هذه المكتبة في pubspec.yaml
import '../../core/constants/app_colors.dart';
import 'main_wrapper.dart';

class ExamResultScreen extends StatelessWidget {
  final String examTitle;
  final int score;
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;

  const ExamResultScreen({
    super.key,
    required this.examTitle,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.wrongAnswers,
  });

  @override
  Widget build(BuildContext context) {
    final double percentage = (score / totalQuestions);
    final int percentageInt = (percentage * 100).toInt();
    
    // تحديد لون ورسالة النتيجة
    Color statusColor;
    String statusMessage;
    String statusIcon;

    if (percentage >= 0.8) {
      statusColor = AppColors.success;
      statusMessage = "OUTSTANDING!";
      statusIcon = "🏆";
    } else if (percentage >= 0.5) {
      statusColor = AppColors.accentYellow;
      statusMessage = "GOOD JOB!";
      statusIcon = "👍";
    } else {
      statusColor = AppColors.error;
      statusMessage = "KEEP PRACTICING";
      statusIcon = "💪";
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              
              // 1. Result Title
              Text(
                "EXAM COMPLETED",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                examTitle.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 48),

              // 2. Circular Indicator
              CircularPercentIndicator(
                radius: 80.0,
                lineWidth: 12.0,
                animation: true,
                percent: percentage,
                center: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$percentageInt%",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 32.0,
                        color: statusColor,
                      ),
                    ),
                    const Text(
                      "SCORE",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10.0,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                circularStrokeCap: CircularStrokeCap.round,
                backgroundColor: AppColors.backgroundSecondary,
                progressColor: statusColor,
              ),

              const SizedBox(height: 32),

              // 3. Status Message
              Text(
                statusIcon,
                style: const TextStyle(fontSize: 40),
              ),
              const SizedBox(height: 8),
              Text(
                statusMessage,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  letterSpacing: 1.0,
                ),
              ),

              const SizedBox(height: 48),

              // 4. Statistics Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      "CORRECT",
                      "$correctAnswers",
                      AppColors.success,
                      LucideIcons.checkCircle2,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      "WRONG",
                      "$wrongAnswers",
                      AppColors.error,
                      LucideIcons.xCircle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      "TOTAL",
                      "$totalQuestions",
                      Colors.white,
                      LucideIcons.list,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // 5. Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // العودة للصفحة الرئيسية ومسح الصفحات السابقة
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MainWrapper()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.backgroundSecondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "BACK TO HOME",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary.withOpacity(0.7),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
