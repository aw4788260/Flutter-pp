import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
// استيراد الصفحات الجديدة
import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';

class DevInfoScreen extends StatelessWidget {
  const DevInfoScreen({super.key});

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
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    "APP INFORMATION",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // App Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 100, 
                            height: 100,
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                          ),
                          
                          Text(
                            "مــــــداد",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Crafted with passion for learners everywhere.",
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 32),
                          
                          // أزرار التواصل (المطورين)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildSocialBtn(
                                icon: LucideIcons.send, 
                                url: "https://t.me/A7MeDWaLiD0",
                              ),
                              const SizedBox(width: 24),
                              _buildSocialBtn(
                                icon: LucideIcons.messageCircle, 
                                url: "https://wa.me/201224984810", // رقم المطور
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Legal & Docs
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 12),
                        child: Text("LEGAL & DOCS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0)),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          // ✅ ربط صفحة سياسة الخصوصية
                          _buildDocItem(
                            context: context,
                            icon: LucideIcons.shield, 
                            title: "Privacy Policy",
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                            }
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          // ✅ ربط صفحة الشروط والأحكام
                          _buildDocItem(
                            context: context,
                            icon: LucideIcons.fileText, 
                            title: "Terms & Conditions",
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsConditionsScreen()));
                            }
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          // ✅ ربط زر الدعم الفني بالرقم المطلوب
                          _buildDocItem(
                            context: context,
                            icon: LucideIcons.phone, // تغيير الأيقونة لهاتف
                            title: "Contact Support",
                            onTap: () async {
                              // الرقم المطلوب: 01559725404 (كود مصر +20)
                              final Uri whatsappUri = Uri.parse("https://wa.me/201559725404");
                              if (await canLaunchUrl(whatsappUri)) {
                                await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: const Text("Could not open WhatsApp"), backgroundColor: AppColors.error),
                                );
                              }
                            }
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Developers Info
                    Text(
                      "DEVELOPERS",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "A7MeD WaLiD & 5@LiD",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Text(
                      "Egypt",
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialBtn({required IconData icon, required String url}) {
    return GestureDetector(
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Icon(icon, color: AppColors.accentYellow, size: 24),
      ),
    );
  }

  Widget _buildDocItem({required BuildContext context, required IconData icon, required String title, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, // تفعيل النقر هنا
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                ),
                child: Icon(icon, color: AppColors.accentYellow, size: 18),
              ),
              const SizedBox(width: 16),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.chevronRight, color: AppColors.textSecondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
