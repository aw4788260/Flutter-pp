import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';
import '../../widgets/custom_text_field.dart';

class ManageTeamScreen extends StatefulWidget {
  const ManageTeamScreen({Key? key}) : super(key: key);

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final TeacherService _teacherService = TeacherService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isObscure = true; // لإخفاء كلمة المرور

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _teacherService.addModerator(
        name: _nameController.text.trim(),
        username: _usernameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تم إضافة المشرف بنجاح"), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // الرجوع للخلف
      }
    } catch (e) {
      if (mounted) {
        // تحسين عرض الخطأ (مثل اسم المستخدم مكرر)
        String errorMsg = e.toString();
        if (errorMsg.contains("Username taken")) {
          errorMsg = "اسم المستخدم هذا محجوز مسبقاً، اختر اسماً آخر.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ: $errorMsg"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إضافة مشرف جديد")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // أيقونة توضيحية
              const Icon(Icons.group_add, size: 60, color: Colors.blueGrey),
              const SizedBox(height: 10),
              const Text(
                "أضف مساعدين لإدارة الطلبات والطلاب.\nالمشرف يملك نفس صلاحياتك ما عدا إدارة المشرفين.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              // حقول الإدخال
              // ✅ تعديل: إضافة label وتغيير prefixIcon
              CustomTextField(
                label: "الاسم الكامل",
                controller: _nameController,
                hintText: "أدخل الاسم الكامل",
                prefixIcon: Icons.person,
                validator: (val) => val!.length < 3 ? "الاسم قصير جداً" : null,
              ),
              const SizedBox(height: 15),
              
              // ✅ تعديل: إضافة label وتغيير prefixIcon
              CustomTextField(
                label: "رقم الهاتف",
                controller: _phoneController,
                hintText: "أدخل رقم الهاتف",
                prefixIcon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (val) => val!.length < 10 ? "رقم الهاتف غير صحيح" : null,
              ),
              const SizedBox(height: 15),

              // ✅ تعديل: إضافة label وتغيير prefixIcon
              CustomTextField(
                label: "اسم المستخدم",
                controller: _usernameController,
                hintText: "اسم المستخدم (للدخول)",
                prefixIcon: Icons.alternate_email,
                validator: (val) => val!.length < 4 ? "يجب أن يكون 4 أحرف على الأقل" : null,
              ),
              const SizedBox(height: 15),

              // حقل كلمة المرور مع زر الإظهار
              TextFormField(
                controller: _passwordController,
                obscureText: _isObscure,
                decoration: InputDecoration(
                  labelText: "كلمة المرور",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _isObscure = !_isObscure),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) => val!.length < 6 ? "كلمة المرور ضعيفة (6 أحرف على الأقل)" : null,
              ),

              const SizedBox(height: 40),

              // زر الإضافة
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue[800],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        "إضافة المشرف",
                        style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
