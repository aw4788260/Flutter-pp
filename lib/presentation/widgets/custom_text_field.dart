import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextEditingController controller;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    required this.controller,
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
        // Label (MATCH: text-[10px] font-bold uppercase tracking-widest text-accent-yellow)
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
            color: AppColors.backgroundSecondary, // bg-background-secondary
            borderRadius: BorderRadius.circular(16), // rounded-m3-lg
            border: Border.all(
              color: _isFocused 
                  ? AppColors.accentYellow.withOpacity(0.5) 
                  : Colors.white.withOpacity(0.05), // border-white/5
            ),
          ),
          child: TextField(
            controller: widget.controller,
            obscureText: widget.isPassword,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            cursorColor: AppColors.accentYellow,
            onTap: () => setState(() => _isFocused = true),
            onTapOutside: (_) => setState(() => _isFocused = false),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              prefixIcon: Icon(
                widget.icon,
                size: 18,
                // MATCH: Icon color change on focus
                color: widget.controller.text.isNotEmpty || _isFocused
                    ? AppColors.accentYellow 
                    : AppColors.textSecondary,
              ),
            ),
            onChanged: (val) => setState(() {}), // لتحديث لون الأيقونة عند الكتابة
          ),
        ),
      ],
    );
  }
}
