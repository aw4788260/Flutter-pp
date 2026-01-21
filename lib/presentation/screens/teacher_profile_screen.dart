import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'course_details_screen.dart'; // للانتقال للكورس عند الضغط عليه

class TeacherProfileScreen extends StatefulWidget {
  final String teacherId;
  const TeacherProfileScreen({super.key, required this.teacherId});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  Map<String, dynamic>? _teacher;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchTeacher();
  }

  Future<void> _fetchTeacher() async {
    try {
      var box = await Hive.openBox('auth_box');
      // ✅ جلب التوكن والبصمة
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      final res = await Dio().get(
        'https://courses.aw478260.dpdns.org/api/public/get-teacher-details',
        queryParameters: {'teacherId': widget.teacherId},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token', // ✅ إرسال التوكن إن وجد
            'x-device-id': deviceId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
        ),
      );
      if (mounted) setState(() { _teacher = res.data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)));
    if (_teacher == null) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: Text("Error loading profile", style: TextStyle(color: Colors.white))));

    final courses = List<Map<String, dynamic>>.from(_teacher!['courses'] ?? []);

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Header & Back ---
              Padding(
                padding: const EdgeInsets.all(24),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                ),
              ),

              // --- Avatar & Info ---
              Center(
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentYellow, width: 2),
                    boxShadow: [BoxShadow(color: AppColors.accentYellow.withOpacity(0.3), blurRadius: 20)],
                  ),
                  child: const Icon(LucideIcons.user, size: 40, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              
              Text(
                _teacher!['name'].toString().toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              
              Text(
                _teacher!['specialty'] ?? 'INSTRUCTOR',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.accentOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),

              // --- Bio Section ---
              Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    const Icon(LucideIcons.quote, color: Colors.white12, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      _teacher!['bio'] ?? 'No bio available.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.8),
                        height: 1.6,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // --- Courses Section ---
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text("AVAILABLE COURSES", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)),
              ),
              const SizedBox(height: 16),

              if (courses.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No courses found", style: TextStyle(color: Colors.white24))))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: courses.length,
                  itemBuilder: (context, index) {
                    final c = courses[index];
                    return GestureDetector(
                      onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CourseDetailsScreen(courseCode: c['code'])));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['title'], 
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${c['price']} EGP", 
                                    style: const TextStyle(color: AppColors.accentYellow, fontSize: 12, fontWeight: FontWeight.bold)
                                  ),
                                ],
                              ),
                            ),
                            const Icon(LucideIcons.chevronRight, color: Colors.white24, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
