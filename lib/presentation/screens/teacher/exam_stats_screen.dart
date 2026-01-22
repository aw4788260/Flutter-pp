import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';

class ExamStatsScreen extends StatefulWidget {
  final String examId;
  final String examTitle;

  const ExamStatsScreen({
    Key? key,
    required this.examId,
    required this.examTitle,
  }) : super(key: key);

  @override
  State<ExamStatsScreen> createState() => _ExamStatsScreenState();
}

class _ExamStatsScreenState extends State<ExamStatsScreen> {
  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
  
  // متغيرات البيانات
  double _averageScore = 0;
  int _totalAttempts = 0;
  List<dynamic> _topStudents = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final data = await _teacherService.getExamStats(widget.examId);
      setState(() {
        _averageScore = double.tryParse(data['average'].toString()) ?? 0;
        _totalAttempts = int.tryParse(data['totalAttempts'].toString()) ?? 0;
        _topStudents = data['topStudents'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("فشل جلب الإحصائيات: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("إحصائيات: ${widget.examTitle}")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // --- بطاقات الملخص (Total Attempts & Average) ---
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: "عدد المحاولات",
                          value: _totalAttempts.toString(),
                          icon: Icons.people_alt,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildStatCard(
                          title: "متوسط الدرجات",
                          value: "${_averageScore.toStringAsFixed(1)}%",
                          icon: Icons.analytics,
                          color: _averageScore >= 50 ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),

                  // --- قائمة الأوائل ---
                  Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(bottom: 10),
                    child: const Text(
                      "🏆 لوحة الشرف (Top 10)",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),

                  if (_topStudents.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.hourglass_empty, size: 40, color: Colors.grey),
                          SizedBox(height: 10),
                          Text("لا توجد محاولات مكتملة حتى الآن"),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _topStudents.length,
                      itemBuilder: (context, index) {
                        final student = _topStudents[index];
                        final isFirst = index == 0;
                        final isSecond = index == 1;
                        final isThird = index == 2;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          // تمييز المراكز الثلاثة الأولى
                          color: isFirst ? Colors.amber[50] : Colors.white, 
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isFirst ? Colors.amber : (isSecond ? Colors.grey[400] : (isThird ? Colors.brown[300] : Colors.blue[100])),
                              child: Text(
                                "${index + 1}",
                                style: TextStyle(
                                  color: (isFirst || isSecond || isThird) ? Colors.white : Colors.blue[800],
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            title: Text(
                              student['name'] ?? "طالب غير معروف",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(student['date']?.toString().split('T')[0] ?? ""),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green[200]!),
                              ),
                              child: Text(
                                "${student['score']}%",
                                style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border(top: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }
}
