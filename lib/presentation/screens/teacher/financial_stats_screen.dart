import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/constants/app_colors.dart';

class FinancialStatsScreen extends StatefulWidget {
  const FinancialStatsScreen({Key? key}) : super(key: key);

  @override
  State<FinancialStatsScreen> createState() => _FinancialStatsScreenState();
}

class _FinancialStatsScreenState extends State<FinancialStatsScreen> {
  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
  
  // Data Variables
  int _totalUniqueStudents = 0;
  double _totalEarnings = 0;
  List<dynamic> _coursesStats = [];
  List<dynamic> _subjectsStats = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final data = await _teacherService.getFinancialStats();
      setState(() {
        _totalUniqueStudents = int.tryParse(data['totalUniqueStudents'].toString()) ?? 0;
        _totalEarnings = double.tryParse(data['totalEarnings'].toString()) ?? 0;
        _coursesStats = data['coursesStats'] ?? [];
        _subjectsStats = data['subjectsStats'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if(mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text("الإحصائيات والأرباح", style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundSecondary,
        iconTheme: const IconThemeData(color: AppColors.accentYellow),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. البطاقات الرئيسية
                  Row(
                    children: [
                      Expanded(child: _buildSummaryCard("إجمالي الطلاب", "$_totalUniqueStudents", Icons.people, Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSummaryCard("إجمالي الأرباح", "$_totalEarnings ج.م", Icons.monetization_on, Colors.green)),
                    ],
                  ),
                  
                  const SizedBox(height: 25),
                  
                  // 2. قسم الكورسات
                  if (_coursesStats.isNotEmpty) ...[
                    const Text("📊 إحصائيات الكورسات", style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ..._coursesStats.map((c) => _buildStatTile(c['title'], c['count'], true)).toList(),
                    const SizedBox(height: 20),
                  ],

                  // 3. قسم المواد
                  if (_subjectsStats.isNotEmpty) ...[
                    const Text("📚 إحصائيات المواد (فردي)", style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ..._subjectsStats.map((s) => _buildStatTile(s['title'], s['count'], false)).toList(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
        border: Border.all(color: Colors.white10)
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatTile(String title, int count, bool isCourse) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10)
      ),
      child: Row(
        children: [
          Icon(isCourse ? Icons.school : Icons.menu_book, color: isCourse ? Colors.orange : Colors.purple, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.backgroundPrimary, borderRadius: BorderRadius.circular(8)),
            child: Text("$count طالب", style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}
