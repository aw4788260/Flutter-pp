import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text("Profile", style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
      ),
      body: const Center(
        child: Text(
          "User Profile",
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
