import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hintText; // ✅ تم تعديل الاسم من hint إلى hintText ليطابق الاستدعاء
  final IconData icon;
  final bool isPassword;
  final TextEditingController controller;
  final int maxLines; // ✅ تمت الإضافة
  final TextInputType keyboardType; // ✅ تمت الإضافة

  const CustomTextField({
    super.key,
    required this.label,
    required this.hintText, // ✅ مطلوب الآن باسم hintText
    required this.icon,
    this.isPassword = false,
    required this.controller,
    this.maxLines = 1, // ✅ قيمة افتراضية
    this.keyboardType = TextInputType.text, // ✅ قيمة افتراضية
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: AppColors.accentYellow,
            ),
          ),
        ),
        
        // Input Container
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isFocused 
                  ? AppColors.accentYellow.withOpacity(0.5) 
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: TextField(
            controller: widget.controller,
            obscureText: widget.isPassword,
            maxLines: widget.maxLines, // ✅ ربط عدد الأسطر
            keyboardType: widget.keyboardType, // ✅ ربط نوع لوحة المفاتيح
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            cursorColor: AppColors.accentYellow,
            onTap: () => setState(() => _isFocused = true),
            onTapOutside: (_) => setState(() => _isFocused = false),
            decoration: InputDecoration(
              hintText: widget.hintText, // ✅ استخدام المتغير المعدل
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              prefixIcon: Icon(
                widget.icon,
                size: 18,
                color: widget.controller.text.isNotEmpty || _isFocused
                    ? AppColors.accentYellow 
                    : AppColors.textSecondary,
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),
        ),
      ],
    );
  }
}
