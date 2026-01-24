import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ للتحكم في الإدخال
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart'; 
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart'; 
import '../../core/services/storage_service.dart';
import '../../core/services/teacher_service.dart'; 
import '../widgets/custom_text_field.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // ✅ مفتاح النموذج للتحقق
  final _formKey = GlobalKey<FormState>();

  // الحقول الأساسية
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _usernameController;
  
  // حقول المدرس الإضافية
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _specialtyController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();

  // قوائم التحكم لبيانات الدفع
  List<TextEditingController> _cashNumberControllers = [];
  List<TextEditingController> _instapayNumberControllers = [];
  List<TextEditingController> _instapayLinkControllers = [];

  // متغيرات الصورة
  File? _selectedImage;
  String? _currentImageUrl;

  bool _isLoading = false;
  bool _isTeacher = false;
  
  final TeacherService _teacherService = TeacherService(); 
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = AppState().userData;
    
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
          _whatsappController.text = box.get('whatsapp_number') ?? "";
          _currentImageUrl = box.get('profile_image');

          List<dynamic> cachedCash = box.get('cash_numbers', defaultValue: []);
          List<dynamic> cachedInstaNums = box.get('instapay_numbers', defaultValue: []);
          List<dynamic> cachedInstaLinks = box.get('instapay_links', defaultValue: []);

          for (var item in cachedCash) _cashNumberControllers.add(TextEditingController(text: item.toString()));
          for (var item in cachedInstaNums) _instapayNumberControllers.add(TextEditingController(text: item.toString()));
          for (var item in cachedInstaLinks) _instapayLinkControllers.add(TextEditingController(text: item.toString()));

          if (_cashNumberControllers.isEmpty) _addController(_cashNumberControllers);
          if (_instapayNumberControllers.isEmpty) _addController(_instapayNumberControllers);
          if (_instapayLinkControllers.isEmpty) _addController(_instapayLinkControllers);
        }
      });
    }
  }

  void _addController(List<TextEditingController> list) {
    setState(() => list.add(TextEditingController()));
  }

  void _removeController(List<TextEditingController> list, int index) {
    setState(() {
      list[index].dispose();
      list.removeAt(index);
    });
  }

  Future<void> _pickImage() async {
    if (!_isTeacher) return; 
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _selectedImage = File(image.path));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _specialtyController.dispose();
    _whatsappController.dispose();
    for (var c in _cashNumberControllers) c.dispose();
    for (var c in _instapayNumberControllers) c.dispose();
    for (var c in _instapayLinkControllers) c.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    // ✅ 1. التحقق من صحة الحقول قبل الإرسال
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');

      List<String> cashList = _cashNumberControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
      List<String> instaNumList = _instapayNumberControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
      List<String> instaLinkList = _instapayLinkControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();

      Map<String, dynamic> dataToSend = {
        'firstName': _nameController.text, 
        'phone': _phoneController.text,
        'username': _usernameController.text,
      };

      if (_isTeacher) {
        dataToSend['bio'] = _bioController.text;
        dataToSend['specialty'] = _specialtyController.text;
        dataToSend['whatsappNumber'] = _whatsappController.text;
        dataToSend['cashNumbersList'] = cashList;
        dataToSend['instapayNumbersList'] = instaNumList;
        dataToSend['instapayLinksList'] = instaLinkList;

        if (_selectedImage != null) {
           String newImageUrl = await _teacherService.uploadProfileImage(_selectedImage!);
           dataToSend['profileImage'] = newImageUrl;
           _currentImageUrl = newImageUrl;
        }
      }

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
        if (AppState().userData != null) {
          AppState().userData!['first_name'] = _nameController.text;
          AppState().userData!['username'] = _usernameController.text;
          AppState().userData!['phone'] = _phoneController.text;
          if (_isTeacher && dataToSend.containsKey('profileImage')) {
             AppState().userData!['profile_image'] = dataToSend['profileImage'];
          }
        }
        
        await box.put('first_name', _nameController.text);
        await box.put('username', _usernameController.text);
        await box.put('phone', _phoneController.text);
        
        if (_isTeacher) {
          await box.put('bio', _bioController.text);
          await box.put('specialty', _specialtyController.text);
          await box.put('whatsapp_number', _whatsappController.text);
          await box.put('cash_numbers', cashList);
          await box.put('instapay_numbers', instaNumList);
          await box.put('instapay_links', instaLinkList);
          if (dataToSend.containsKey('profileImage')) await box.put('profile_image', dataToSend['profileImage']);
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
                child: Form( // ✅ تغليف الحقول بنموذج للتحقق
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isTeacher) ...[
                        Center(
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Stack(
                              children: [
                                Container(
                                  width: 100, height: 100,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.accentYellow, width: 2),
                                    image: _selectedImage != null
                                        ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                                        : (_currentImageUrl != null && _currentImageUrl!.isNotEmpty
                                            ? DecorationImage(image: NetworkImage(_currentImageUrl!), fit: BoxFit.cover)
                                            : null),
                                  ),
                                  child: (_selectedImage == null && (_currentImageUrl == null || _currentImageUrl!.isEmpty))
                                      ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0, right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(color: AppColors.accentYellow, shape: BoxShape.circle),
                                    child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Center(child: Text("Tap to change photo", style: TextStyle(color: Colors.grey, fontSize: 10))),
                        const SizedBox(height: 20),
                      ],

                      CustomTextField(
                        label: "Full Name",
                        controller: _nameController,
                        hintText: "Enter your full name",
                        prefixIcon: LucideIcons.user,
                        validator: (value) => value == null || value.isEmpty ? "Name is required" : null,
                      ),
                      const SizedBox(height: 20),
                      
                      CustomTextField(
                        label: "Phone Number",
                        controller: _phoneController,
                        hintText: "01xxxxxxxxx",
                        prefixIcon: LucideIcons.phone,
                        keyboardType: TextInputType.phone,
                        validator: (value) => value == null || value.length < 11 ? "Invalid phone number" : null,
                      ),
                      const SizedBox(height: 20),
                      
                      // ✅ حقل اسم المستخدم مع القيود المطلوبة
                      CustomTextField(
                        label: "Username",
                        controller: _usernameController,
                        hintText: "English letters & numbers only",
                        prefixIcon: LucideIcons.atSign,
                        // 1. منع الكتابة: يسمح فقط بالحروف الإنجليزية (صغيرة/كبيرة) والأرقام
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                        ],
                        // 2. التحقق النهائي: للتأكد من عدم وجود مسافات أو رموز
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Username is required";
                          if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value)) {
                            return "Only English letters & numbers allowed (No spaces)";
                          }
                          return null;
                        },
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
                          label: "WhatsApp Number (For Students)",
                          controller: _whatsappController,
                          hintText: "201xxxxxxxxx",
                          prefixIcon: LucideIcons.messageCircle,
                          keyboardType: TextInputType.phone,
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 6, left: 8, bottom: 20),
                          child: Text("Enter number with country code without '+' (e.g. 201xxxxxxxxx)", style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ),
                        
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
                        const SizedBox(height: 10),
                        const Text("PAYMENT METHODS", style: TextStyle(color: AppColors.accentYellow, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const SizedBox(height: 20),

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
            ),

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
        
        ...List.generate(controllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: "", 
                    controller: controllers[index],
                    hintText: hint,
                    prefixIcon: icon,
                    keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => onRemove(index),
                  child: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 24),
                ),
              ],
            ),
          );
        }),
        
        if (controllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text("Click + to add a number/link", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}
