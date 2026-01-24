import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart'; 
import '../../../core/services/teacher_service.dart';
import '../../../core/services/storage_service.dart'; 

class StudentRequestsScreen extends StatefulWidget {
  const StudentRequestsScreen({Key? key}) : super(key: key);

  @override
  State<StudentRequestsScreen> createState() => _StudentRequestsScreenState();
}

class _StudentRequestsScreenState extends State<StudentRequestsScreen> {
  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
  List<dynamic> _requests = [];

  // بيانات المصادقة للصور
  String? _token;
  String? _deviceId;
  final String _appSecret = const String.fromEnvironment('APP_SECRET');

  final String _baseUrl = "https://courses.aw478260.dpdns.org"; 
  String get _receiptProxyUrl => "$_baseUrl/api/admin/file-proxy?type=receipts&filename=";

  @override
  void initState() {
    super.initState();
    // ✅ الحل الجذري: تشغيل دالة تحميل موحدة متسلسلة
    _initialLoad();
  }

  /// ✅ دالة تحميل موحدة تضمن تحميل الهوية (Device ID) قبل البيانات
  Future<void> _initialLoad() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. انتظار تحميل بيانات المصادقة من الذاكرة المحلية أولاً
      var box = await StorageService.openBox('auth_box');
      final loadedToken = box.get('jwt_token');
      final loadedDevice = box.get('device_id');

      // 2. تخزينها في المتغيرات
      _token = loadedToken;
      _deviceId = loadedDevice;

      // طباعة للتأكد من أن القيم موجودة قبل إرسال أي طلب
      debugPrint("Auth Loaded: DeviceID=$_deviceId");

      // 3. الآن فقط نقوم بجلب الطلبات من السيرفر
      await _loadRequestsData();

    } catch (e) {
      debugPrint("Error in initial load: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ في التحميل: $e"), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// دالة فرعية لجلب البيانات فقط (بدون إعادة تحميل التوكن)
  Future<void> _loadRequestsData() async {
    try {
      final data = await _teacherService.getPendingRequests();
      if (mounted) {
        setState(() {
          _requests = data;
          _isLoading = false; // ✅ هنا فقط نوقف التحميل بعد جاهزية كل شيء
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        throw e; // نعيد رمي الخطأ ليمسكه الـ catch الرئيسي
      }
    }
  }

  /// إعادة تحميل القائمة (مثلاً بعد القبول/الرفض)
  Future<void> _refreshRequests() async {
     setState(() => _isLoading = true);
     await _loadRequestsData();
  }

  Future<void> _handleDecision(String requestId, bool approve) async {
    String? rejectionReason;

    if (!approve) {
      rejectionReason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          String reason = "";
          return AlertDialog(
            backgroundColor: AppColors.backgroundSecondary,
            title: const Text("سبب الرفض", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            content: TextField(
              onChanged: (val) => reason = val,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "اكتب سبب الرفض هنا...",
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.backgroundPrimary,
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text("إلغاء", style: TextStyle(color: AppColors.textSecondary))
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, reason),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("تأكيد الرفض", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (rejectionReason == null) return;
    }

    try {
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
            backgroundColor: approve ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      _refreshRequests();
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشلت العملية: $e"), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showFullImage(String url) {
    // نتأكد للمرة الأخيرة أن البيانات موجودة
    if (_deviceId == null || _token == null) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطأ: بيانات المصادقة غير جاهزة"), backgroundColor: AppColors.error),
       );
       return;
    }

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
                  // ✅ الهيدرز الضرورية لعرض الصورة
                  httpHeaders: {
                    'Authorization': 'Bearer $_token',
                    'x-device-id': _deviceId!, // علامة التعجب لأننا تأكدنا أنه ليس null
                    'x-app-secret': _appSecret,
                  },
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.backgroundSecondary,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Icon(Icons.broken_image_rounded, color: AppColors.error, size: 50),
                         SizedBox(height: 8),
                         Text("تعذر تحميل الصورة - تأكد من الاتصال", style: TextStyle(color: AppColors.textSecondary)),
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
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text("طلبات الاشتراك المعلقة", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.accentYellow),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded, size: 80, color: AppColors.textSecondary.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      const Text("لا توجد طلبات معلقة حالياً", style: TextStyle(color: AppColors.textSecondary, fontSize: 18)),
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
    final String? filename = req['payment_file_path'];
    final bool hasImage = filename != null && filename.isNotEmpty;
    final String imageUrl = hasImage ? "$_receiptProxyUrl$filename" : "";

    // ✅ استخراج الملاحظة من العمود الجديد
    final String? userNote = req['user_note'];
    final bool hasNote = userNote != null && userNote.trim().isNotEmpty;

    String dateStr = req['created_at'] ?? "";
    if (dateStr.length > 10) dateStr = dateStr.substring(0, 10);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ================== القسم العلوي (الصورة والبيانات) ==================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    if (hasImage) _showFullImage(imageUrl);
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      color: AppColors.backgroundPrimary,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: hasImage
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              httpHeaders: {
                                'Authorization': 'Bearer $_token',
                                'x-device-id': _deviceId ?? '',
                                'x-app-secret': _appSecret,
                              },
                              fit: BoxFit.cover,
                              placeholder: (c, u) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentYellow)),
                              errorWidget: (c, u, e) => const Icon(Icons.broken_image_rounded, color: AppColors.textSecondary),
                            )
                          : const Center(child: Icon(Icons.receipt_long_rounded, color: AppColors.textSecondary, size: 35)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
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
                               style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                               overflow: TextOverflow.ellipsis,
                             ),
                           ),
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             decoration: BoxDecoration(color: AppColors.backgroundPrimary, borderRadius: BorderRadius.circular(8)),
                             child: Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
            
            Divider(height: 24, color: Colors.white.withOpacity(0.1)),

            // ================== التفاصيل والسعر والملاحظة ==================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start, // محاذاة للأعلى لضمان تناسق العمودين
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      // صندوق تفاصيل الكورس
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundPrimary.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accentBlue.withOpacity(0.3))
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.shopping_cart_outlined, size: 16, color: AppColors.accentBlue),
                                SizedBox(width: 6),
                                Text("المحتوى المطلوب:", style: TextStyle(color: AppColors.accentBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              req['course_title'] ?? 'غير محدد',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      
                      // ✅ عرض الملاحظة هنا بشكل منفصل وبتصميم مميز
                      if (hasNote) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1), // خلفية شفافة صفراء
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withOpacity(0.3)), // حدود صفراء خفيفة
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 16, color: Colors.amber),
                                  SizedBox(width: 6),
                                  Text("ملاحظة الطالب:", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                userNote,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                
                // صندوق السعر
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundPrimary.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: AppColors.success.withOpacity(0.3))
                    ),
                    child: Column(
                      children: [
                        const Text("الإجمالي", style: TextStyle(color: AppColors.success, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(
                          "${req['total_price'] ?? 0}", 
                          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 18)
                        ),
                        const Text("EGP", style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),

            // ================== الأزرار ==================
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleDecision(req['id'].toString(), false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withOpacity(0.5), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text("رفض الطلب", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleDecision(req['id'].toString(), true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                     icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
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

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
