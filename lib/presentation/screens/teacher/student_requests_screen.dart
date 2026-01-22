import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // تأكد من وجود هذه المكتبة
import '../../../core/services/teacher_service.dart';

class StudentRequestsScreen extends StatefulWidget {
  const StudentRequestsScreen({Key? key}) : super(key: key);

  @override
  State<StudentRequestsScreen> createState() => _StudentRequestsScreenState();
}

class _StudentRequestsScreenState extends State<StudentRequestsScreen> {
  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final data = await _teacherService.getPendingRequests();
      setState(() {
        _requests = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDecision(String requestId, bool approve) async {
    String? rejectionReason;

    if (!approve) {
      // في حالة الرفض، نطلب السبب أولاً
      rejectionReason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          String reason = "";
          return AlertDialog(
            title: const Text("سبب الرفض"),
            content: TextField(
              onChanged: (val) => reason = val,
              decoration: const InputDecoration(hintText: "اكتب سبب الرفض هنا..."),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, reason),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("تأكيد الرفض"),
              ),
            ],
          );
        },
      );

      if (rejectionReason == null) return; // تم الإلغاء
    }

    // تنفيذ القرار
    try {
      await _teacherService.handleRequest(requestId, approve, reason: rejectionReason);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? "تم قبول الطالب بنجاح" : "تم رفض الطلب"),
          backgroundColor: approve ? Colors.green : Colors.red,
        ),
      );
      
      // تحديث القائمة
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("فشلت العملية: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("طلبات الاشتراك المعلقة")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text("لا توجد طلبات معلقة حالياً"))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    final user = req['users'] ?? {}; // بيانات المستخدم إن وجدت
                    final receiptUrl = req['receipt_url']; // افترضنا أن هذا اسم الحقل

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // صورة الإيصال
                                GestureDetector(
                                  onTap: () => receiptUrl != null ? _showFullImage(receiptUrl) : null,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: receiptUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: receiptUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (c, u) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                            errorWidget: (c, u, e) => const Icon(Icons.broken_image, color: Colors.grey),
                                          )
                                        : const Icon(Icons.receipt, color: Colors.grey),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // بيانات الطالب
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        req['user_name'] ?? "غير معروف",
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text("📱 ${req['phone'] ?? 'بدون رقم'}", style: TextStyle(color: Colors.grey[700])),
                                      const SizedBox(height: 4),
                                      Text("📧 ${req['user_username'] ?? '-'}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          "الكورس المطلوب: ${req['courses']?['title'] ?? 'غير محدد'}",
                                          style: TextStyle(color: Colors.blue[800], fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            // أزرار التحكم
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _handleDecision(req['id'], false),
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    label: const Text("رفض", style: TextStyle(color: Colors.red)),
                                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _handleDecision(req['id'], true),
                                    icon: const Icon(Icons.check, color: Colors.white),
                                    label: const Text("قبول وتفعيل", style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
