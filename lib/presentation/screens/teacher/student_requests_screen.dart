import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
// تأكد من استيراد الـ Constants الخاصة بك إذا كانت تحتوي على الـ Base URL
// import '../../../core/constants/api_constants.dart'; 
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

  // ⚠️ هام: ضع رابط السيرفر الأساسي الخاص بك هنا
  // يفضل جلبه من ملف constants مركزي في مشروعك
  final String _baseUrl = "https://courses.aw478260.dpdns.org"; 
  // مسار البروكسي المسؤول عن عرض صور الإيصالات
  String get _receiptProxyUrl => "$_baseUrl/api/admin/file-proxy?type=receipts&filename=";


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
      rejectionReason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          String reason = "";
          return AlertDialog(
            title: const Text("سبب الرفض", style: TextStyle(fontWeight: FontWeight.bold)),
            content: TextField(
              onChanged: (val) => reason = val,
              decoration: InputDecoration(
                hintText: "اكتب سبب الرفض هنا...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text("إلغاء", style: TextStyle(color: Colors.grey))
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, reason),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("تأكيد الرفض", style: TextStyle(color: Colors.white)),
              ),
            ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          );
        },
      );

      if (rejectionReason == null) return;
    }

    try {
      // إظهار مؤشر تحميل مؤقت
      ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text("جاري تنفيذ العملية..."), duration: Duration(seconds: 1)),
      );

      await _teacherService.handleRequest(requestId, approve, reason: rejectionReason);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(approve ? Icons.check_circle : Icons.cancel, color: Colors.white),
                const SizedBox(width: 8),
                Text(approve ? "تم قبول الطالب بنجاح" : "تم رفض الطلب"),
              ],
            ),
            backgroundColor: approve ? Colors.green[700] : Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      _loadRequests();
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشلت العملية: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: url,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.white,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Icon(Icons.broken_image_rounded, color: Colors.red, size: 50),
                         SizedBox(height: 8),
                         Text("تعذر تحميل الصورة"),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], // خلفية أفتح قليلاً
      appBar: AppBar(
        title: const Text("طلبات الاشتراك المعلقة", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text("لا توجد طلبات معلقة حالياً", style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) => _buildRequestCard(_requests[index]),
                ),
    );
  }

  Widget _buildRequestCard(dynamic req) {
    // 1. بناء رابط الصورة الصحيح
    final String? filename = req['payment_file_path'];
    final bool hasImage = filename != null && filename.isNotEmpty;
    final String imageUrl = hasImage ? "$_receiptProxyUrl$filename" : "";

    // تنسيق التاريخ (اختياري - يمكن تحسينه باستخدام مكتبة intl)
    String dateStr = req['created_at'] ?? "";
    if (dateStr.length > 10) dateStr = dateStr.substring(0, 10);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ================== القسم العلوي: البيانات والصورة ==================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🖼️ الصورة المصغرة (Thumbnail)
                GestureDetector(
                  onTap: () {
                    if (hasImage) _showFullImage(imageUrl);
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      color: Colors.grey.shade50,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))
                      ]
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: hasImage
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (c, u) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              errorWidget: (c, u, e) => const Icon(Icons.broken_image_rounded, color: Colors.grey),
                            )
                          : const Center(child: Icon(Icons.receipt_long_rounded, color: Colors.grey, size: 35)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // ℹ️ بيانات الطالب
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                           Expanded(
                             child: Text(
                               req['user_name'] ?? "اسم غير معروف",
                               style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.black87),
                               overflow: TextOverflow.ellipsis,
                             ),
                           ),
                           // تاريخ الطلب
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                             child: Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                           )
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(Icons.phone_android_rounded, req['phone'] ?? '---'),
                      const SizedBox(height: 4),
                      _buildInfoRow(Icons.alternate_email_rounded, req['user_username'] ?? '---'),
                    ],
                  ),
                ),
              ],
            ),
            
            Divider(height: 24, color: Colors.grey[200]),

            // ================== القسم الأوسط: المحتوى والسعر ==================
            Row(
              children: [
                // المحتوى المطلوب
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shopping_cart_outlined, size: 16, color: Colors.blue[800]),
                            const SizedBox(width: 6),
                            Text("المحتوى المطلوب:", style: TextStyle(color: Colors.blue[800], fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          req['course_title'] ?? 'غير محدد',
                          style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // السعر الإجمالي
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: Colors.green.shade100)
                    ),
                    child: Column(
                      children: [
                        Text("الإجمالي", style: TextStyle(color: Colors.green[700], fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(
                          "${req['total_price'] ?? 0}", 
                          style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w900, fontSize: 20)
                        ),
                        Text("EGP", style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),

            // ================== القسم السفلي: أزرار التحكم ==================
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleDecision(req['id'].toString(), false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade200, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text("رفض الطلب", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleDecision(req['id'].toString(), true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                     icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text("قبول وتفعيل", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // دالة مساعدة صغيرة لعرض سطر معلومات مع أيقونة
  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
