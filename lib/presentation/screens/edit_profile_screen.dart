import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
import '../../core/services/storage_service.dart';
import '../widgets/custom_text_field.dart'; // ✅ استيراد CustomTextField

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _usernameController;
  
  // حقول إضافية للمعلم
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _specialtyController = TextEditingController();

  bool _isLoading = false;
  bool _isTeacher = false; // لتحديد هل نظهر الحقول الإضافية أم لا
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = AppState().userData;
    
    // تحميل البيانات الأساسية
    _nameController = TextEditingController(text: user?['first_name'] ?? "");
    _phoneController = TextEditingController(text: user?['phone'] ?? "");
    _usernameController = TextEditingController(text: user?['username'] ?? "");

    // التحقق من الصلاحية (معلم أم لا) وجلب بياناته الإضافية
    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
        if (_isTeacher) {
          _bioController.text = box.get('bio') ?? "";
          _specialtyController.text = box.get('specialty') ?? "";
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _specialtyController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');

      // تجهيز البيانات للإرسال
      Map<String, dynamic> dataToSend = {
        'firstName': _nameController.text,
        'phone': _phoneController.text,
        'username': _usernameController.text,
      };

      // إضافة بيانات المعلم إذا وجد
      if (_isTeacher) {
        dataToSend['bio'] = _bioController.text;
        dataToSend['specialty'] = _specialtyController.text;
      }

      // تحديد الـ Endpoint المناسب
      String endpoint = _isTeacher ? '$_baseUrl/api/teacher/update-profile' : '$_baseUrl/api/student/update-profile';

      final res = await Dio().post(
        endpoint,
        data: dataToSend,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'), 
        }),
      );

      if (res.statusCode == 200 && res.data['success'] == true) {
        // تحديث حالة التطبيق (في الذاكرة)
        if (AppState().userData != null) {
          AppState().userData!['first_name'] = _nameController.text;
          AppState().userData!['username'] = _usernameController.text;
          AppState().userData!['phone'] = _phoneController.text;
        }
        
        // تحديث التخزين المحلي
        await box.put('first_name', _nameController.text);
        await box.put('username', _usernameController.text);
        await box.put('phone', _phoneController.text);
        
        if (_isTeacher) {
          await box.put('bio', _bioController.text);
          await box.put('specialty', _specialtyController.text);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Updated Successfully"), backgroundColor: AppColors.success));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = "Failed to update profile";
        if(e is DioException) {
           errorMsg = e.response?.data['message'] ?? errorMsg;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header ---
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
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "EDIT PROFILE",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
                  ),
                ],
              ),
            ),

            // --- Form Fields ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ استخدام CustomTextField بدلاً من _buildInputField
                    CustomTextField(
                      label: "Full Name",
                      controller: _nameController,
                      hintText: "Enter your full name",
                      prefixIcon: LucideIcons.user,
                    ),
                    const SizedBox(height: 20),
                    
                    CustomTextField(
                      label: "Phone Number",
                      controller: _phoneController,
                      hintText: "01xxxxxxxxx",
                      prefixIcon: LucideIcons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                    
                    CustomTextField(
                      label: "Username",
                      controller: _usernameController,
                      hintText: "Choose a username",
                      prefixIcon: LucideIcons.atSign,
                    ),
                    
                    // 🟢 حقول إضافية للمعلم فقط
                    if (_isTeacher) ...[
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 10),
                      const Text("TEACHER INFO", style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 15),
                      
                      CustomTextField(
                        label: "Specialty / Job Title",
                        controller: _specialtyController,
                        hintText: "e.g. Physics Teacher",
                        prefixIcon: LucideIcons.briefcase,
                      ),
                      const SizedBox(height: 20),
                      
                      CustomTextField(
                        label: "Bio / About Me",
                        controller: _bioController,
                        hintText: "Tell students about yourself...",
                        prefixIcon: LucideIcons.fileText,
                        keyboardType: TextInputType.multiline,
                        maxLines: 3,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // --- Save Button ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 10,
                    shadowColor: AppColors.accentYellow.withOpacity(0.2),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.backgroundPrimary))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(LucideIcons.save, size: 18),
                          SizedBox(width: 12),
                          Text("SAVE CHANGES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
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
}
