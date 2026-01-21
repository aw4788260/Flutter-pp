import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  bool _loading = true;
  List<dynamic> _requests = [];
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    try {
      var box = await Hive.openBox('auth_box');
      // ✅ جلب التوكن وبصمة الجهاز بدلاً من user_id
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');
      
      final res = await Dio().get(
        '$_baseUrl/api/student/my-requests',
        options: Options(headers: {
          'Authorization': 'Bearer $token', // ✅ الهيدر الجديد
          'x-device-id': deviceId,
          'x-app-secret': const String.fromEnvironment('APP_SECRET'),
        }),
      );
      
      if (mounted) {
        setState(() {
          _requests = res.data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MY REQUESTS",
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "TRACK YOUR ORDERS",
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- List ---
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
                  : _requests.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.inbox, size: 48, color: AppColors.textSecondary.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(
                                "NO REQUESTS FOUND",
                                style: TextStyle(
                                  color: AppColors.textSecondary.withOpacity(0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            return _buildRequestCard(_requests[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    String status = req['status'] ?? 'pending';
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'approved':
        statusColor = AppColors.success;
        statusIcon = LucideIcons.checkCircle;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        statusIcon = LucideIcons.xCircle;
        break;
      default:
        statusColor = AppColors.accentYellow;
        statusIcon = LucideIcons.clock;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "#${req['id']}", 
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)
                ),
              ),
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    status.toUpperCase(), 
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            req['course_title'] ?? 'Unknown Item', 
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "${req['total_price']} EGP", 
            style: const TextStyle(color: AppColors.accentYellow, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          
          if (status == 'rejected' && req['rejection_reason'] != null)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.2)),
              ),
              child: Text(
                "Reason: ${req['rejection_reason']}", 
                style: const TextStyle(color: AppColors.error, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
