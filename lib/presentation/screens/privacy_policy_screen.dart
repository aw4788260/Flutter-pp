import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                      ),
                      child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "سياسة الخصوصية\nPRIVACY POLICY",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      _buildSection(
                        "1. جمع البيانات والأذونات",
                        "1. Data Collection & Permissions",
                        "نقوم بجمع 'معرف الجهاز' (Device ID) لربط حسابك بجهاز واحد فقط لضمان الأمان. كما نستخدم خدمة الإشعارات (Notifications) لعرض حالة تحميل الدروس في الخلفية لضمان استمرار التحميل عند الخروج من التطبيق.",
                        "We collect your 'Device ID' to link your account to a single device for security. We also use Notifications to display download progress in the background, ensuring downloads continue even when the app is minimized."
                      ),
                      Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 40),
                      
                      _buildSection(
                        "2. متطلبات الأمان للجهاز",
                        "2. Device Security Requirements",
                        "لضمان حماية المحتوى، لا يمكن استخدام التطبيق على الأجهزة التي تم كسر حمايتها (Root/Jailbreak) أو الأجهزة التي تم تفعيل 'خيارات المطور' (Developer Options) بها. سيقوم التطبيق بالتحقق من ذلك وإيقاف العمل تلقائياً.",
                        "To ensure content protection, the app cannot be used on Rooted/Jailbroken devices or devices with 'Developer Options' enabled. The app will automatically verify this and stop working if detected."
                      ),
                      Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 40),

                      _buildSection(
                        "3. حماية المحتوى",
                        "3. Content Protection",
                        "جميع المواد التعليمية مشفرة ومحمية. أي محاولة لتسجيل الشاشة أو استخدام برامج خارجية ستؤدي إلى حظر الحساب فوراً.",
                        "All educational materials are encrypted and protected. Any attempt to screen record or use third-party software will result in immediate account suspension."
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String arTitle, String enTitle, String arBody, String enBody) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end, // العربية محاذاة لليمين
      children: [
        // العربية
        Text(
          arTitle,
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          arBody,
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.textPrimary, height: 1.6, fontSize: 14),
        ),
        
        const SizedBox(height: 16),
        
        // الإنجليزية
        Align(
          alignment: Alignment.centerLeft, // الإنجليزية محاذاة لليسار
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enTitle,
                style: TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                enBody,
                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), height: 1.4, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
