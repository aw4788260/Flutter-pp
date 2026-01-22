import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
import '../../core/services/storage_service.dart';
import '../widgets/custom_text_field.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // الحقول الأساسية
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _usernameController;
  
  // حقول المدرس الإضافية
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _specialtyController = TextEditingController();

  // ✅ قوائم التحكم لبيانات الدفع الثلاثة
  List<TextEditingController> _cashNumberControllers = [];
  List<TextEditingController> _instapayNumberControllers = [];
  List<TextEditingController> _instapayLinkControllers = [];

  bool _isLoading = false;
  bool _isTeacher = false;
  
  // تأكد من أن الرابط صحيح
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

    var box = await StorageService.openBox('auth_box');
    String? role = box.get('role');
    
    if (mounted) {
      setState(() {
        _isTeacher = role == 'teacher';
        
        if (_isTeacher) {
          _bioController.text = box.get('bio') ?? "";
          _specialtyController.text = box.get('specialty') ?? "";

          // ✅ تحميل قوائم الدفع المحفوظة محلياً (إن وجدت)
          List<dynamic> cachedCash = box.get('cash_numbers', defaultValue: []);
          List<dynamic> cachedInstaNums = box.get('instapay_numbers', defaultValue: []);
          List<dynamic> cachedInstaLinks = box.get('instapay_links', defaultValue: []);

          // تعبئة المتحكمات (Controllers) بالبيانات
          for (var item in cachedCash) {
            _cashNumberControllers.add(TextEditingController(text: item.toString()));
          }
          for (var item in cachedInstaNums) {
            _instapayNumberControllers.add(TextEditingController(text: item.toString()));
          }
          for (var item in cachedInstaLinks) {
            _instapayLinkControllers.add(TextEditingController(text: item.toString()));
          }

          // إضافة حقل فارغ افتراضي فقط إذا كانت القوائم فارغة تماماً
          if (_cashNumberControllers.isEmpty) _addController(_cashNumberControllers);
          if (_instapayNumberControllers.isEmpty) _addController(_instapayNumberControllers);
          if (_instapayLinkControllers.isEmpty) _addController(_instapayLinkControllers);
        }
      });
    }
  }

  // ✅ دالة مساعدة لإضافة حقل جديد لأي قائمة
  void _addController(List<TextEditingController> list) {
    setState(() {
      list.add(TextEditingController());
    });
  }

  // ✅ دالة مساعدة لحذف حقل من أي قائمة
  void _removeController(List<TextEditingController> list, int index) {
    setState(() {
      list[index].dispose(); // تنظيف الذاكرة
      list.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _specialtyController.dispose();
    
    // تنظيف قوائم المتحكمات
    for (var c in _cashNumberControllers) c.dispose();
    for (var c in _instapayNumberControllers) c.dispose();
    for (var c in _instapayLinkControllers) c.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');

      // ✅ استخراج النصوص من المتحكمات وتنظيفها من الفراغات
      List<String> cashList = _cashNumberControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      List<String> instaNumList = _instapayNumberControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      List<String> instaLinkList = _instapayLinkControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      // تجهيز البيانات للإرسال
      Map<String, dynamic> dataToSend = {
        'firstName': _nameController.text, // تأكدنا من توحيد الاسم حسب الباك إند (firstName أو name)
        'phone': _phoneController.text,
        'username': _usernameController.text,
      };

      if (_isTeacher) {
        dataToSend['bio'] = _bioController.text;
        dataToSend['specialty'] = _specialtyController.text;
        // ✅ إرسال القوائم الثلاث
        dataToSend['cashNumbersList'] = cashList;
        dataToSend['instapayNumbersList'] = instaNumList;
        dataToSend['instapayLinksList'] = instaLinkList;
      }

      // تحديد الرابط
      String endpoint = _isTeacher 
          ? '$_baseUrl/api/teacher/update-profile' 
          : '$_baseUrl/api/student/update-profile';

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
        // تحديث البيانات في الذاكرة (AppState)
        if (AppState().userData != null) {
          AppState().userData!['first_name'] = _nameController.text;
          AppState().userData!['username'] = _usernameController.text;
          AppState().userData!['phone'] = _phoneController.text;
        }
        
        // تحديث التخزين المحلي (Hive)
        await box.put('first_name', _nameController.text);
        await box.put('username', _usernameController.text);
        await box.put('phone', _phoneController.text);
        
        if (_isTeacher) {
          await box.put('bio', _bioController.text);
          await box.put('specialty', _specialtyController.text);
          // ✅ حفظ القوائم محلياً
          await box.put('cash_numbers', cashList);
          await box.put('instapay_numbers', instaNumList);
          await box.put('instapay_links', instaLinkList);
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
           errorMsg = e.response?.data['message'] ?? e.response?.data['error'] ?? errorMsg;
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

                      const SizedBox(height: 30),
                      const Divider(color: Colors.white10),
                      
                      // ✅ قسم بيانات الدفع
                      const SizedBox(height: 10),
                      const Text("PAYMENT METHODS", style: TextStyle(color: AppColors.accentYellow, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 20),

                      // 1. Cash Numbers Section
                      _buildDynamicList(
                        title: "Cash Wallet Numbers",
                        controllers: _cashNumberControllers,
                        hint: "Enter Wallet Number",
                        onAdd: () => _addController(_cashNumberControllers),
                        onRemove: (idx) => _removeController(_cashNumberControllers, idx),
                        icon: Icons.account_balance_wallet,
                        isNumeric: true,
                      ),

                      const SizedBox(height: 24),

                      // 2. InstaPay Numbers Section
                      _buildDynamicList(
                        title: "InstaPay Numbers",
                        controllers: _instapayNumberControllers,
                        hint: "Enter InstaPay Phone Number",
                        onAdd: () => _addController(_instapayNumberControllers),
                        onRemove: (idx) => _removeController(_instapayNumberControllers, idx),
                        icon: Icons.phone_iphone,
                        isNumeric: true,
                      ),

                      const SizedBox(height: 24),

                      // 3. InstaPay Links/Usernames Section
                      _buildDynamicList(
                        title: "InstaPay Links / Usernames",
                        controllers: _instapayLinkControllers,
                        hint: "username@instapay or Link",
                        onAdd: () => _addController(_instapayLinkControllers),
                        onRemove: (idx) => _removeController(_instapayLinkControllers, idx),
                        icon: LucideIcons.link,
                        isNumeric: false,
                      ),
                      
                      const SizedBox(height: 40),
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

  // ✅ ويدجت ديناميكية لبناء القوائم (Dynamic List Builder)
  Widget _buildDynamicList({
    required String title,
    required List<TextEditingController> controllers,
    required String hint,
    required VoidCallback onAdd,
    required Function(int) onRemove,
    required IconData icon,
    bool isNumeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            InkWell(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.accentOrange.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.add, color: AppColors.accentOrange, size: 18),
              ),
            )
          ],
        ),
        const SizedBox(height: 10),
        
        // عرض قائمة الحقول
        ...List.generate(controllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: "", // لا نحتاج لعنوان هنا
                    controller: controllers[index],
                    hintText: hint,
                    prefixIcon: icon,
                    keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
                  ),
                ),
                const SizedBox(width: 10),
                // زر الحذف (يظهر دائماً حتى لو كان الحقل وحيداً، لتمكين المستخدم من تفريغ القائمة)
                InkWell(
                  onTap: () => onRemove(index),
                  child: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 24),
                ),
              ],
            ),
          );
        }),
        
        // رسالة صغيرة إذا كانت القائمة فارغة
        if (controllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text("Click + to add a number/link", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}
