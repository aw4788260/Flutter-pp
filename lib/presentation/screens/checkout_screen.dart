import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ إضافة الاستيراد
import '../../core/constants/app_colors.dart';
import 'main_wrapper.dart'; 

class CheckoutScreen extends StatefulWidget {
  final double amount;
  final Map<String, dynamic> paymentInfo;
  final List<Map<String, dynamic>> selectedItems;

  const CheckoutScreen({
    super.key,
    required this.amount,
    required this.paymentInfo,
    required this.selectedItems,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final TextEditingController _noteController = TextEditingController();
  File? _receiptImage;
  bool _isUploading = false;
  final String _baseUrl = 'https://courses.aw478260.dpdns.org';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _receiptImage = File(pickedFile.path);
      });
    }
  }

  // ✅ دالة فتح الروابط
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch link"), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _submitOrder() async {
    if (_receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload the payment receipt image"), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      var box = await Hive.openBox('auth_box');
      final userId = box.get('user_id');

      String fileName = _receiptImage!.path.split('/').last;
      
      FormData formData = FormData.fromMap({
        'receiptFile': await MultipartFile.fromFile(_receiptImage!.path, filename: fileName),
        'user_note': _noteController.text,
        'selectedItems': jsonEncode(widget.selectedItems),
      });

      final response = await Dio().post(
        '$_baseUrl/api/student/request-course',
        data: formData,
        options: Options(
          headers: {
            'x-user-id': userId,
            'x-app-secret': const String.fromEnvironment('APP_SECRET'),
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.backgroundSecondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Column(
                children: const [
                  Icon(LucideIcons.checkCircle, color: AppColors.success, size: 48),
                  SizedBox(height: 16),
                  Text("REQUEST SENT", style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                "We have received your request.\nYou will be notified once approved.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MainWrapper()),
                      (route) => false,
                    );
                  },
                  child: const Text("OK", style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.data['error'] ?? "Failed to send request"), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connection Error"), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String vodafone = widget.paymentInfo['vodafone_cash_number'] ?? '';
    final String instapayNum = widget.paymentInfo['instapay_number'] ?? '';
    final String instapayLink = widget.paymentInfo['instapay_link'] ?? ''; // ✅ جلب رابط انستا باي

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "CHECKOUT",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
                      ),
                      child: Column(
                        children: [
                          const Text("TOTAL AMOUNT", style: TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text("${widget.amount} EGP", style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.accentYellow)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (vodafone.isNotEmpty)
                      _buildPaymentMethod("VODAFONE CASH", vodafone, LucideIcons.smartphone),
                    
                    if (instapayNum.isNotEmpty)
                      _buildPaymentMethod(
                        "INSTAPAY", 
                        instapayNum, 
                        LucideIcons.creditCard,
                        link: instapayLink // ✅ تمرير الرابط
                      ),

                    const SizedBox(height: 32),
                    
                    const Text("UPLOAD RECEIPT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _receiptImage != null ? AppColors.accentYellow : Colors.white.withOpacity(0.1),
                            style: BorderStyle.solid, 
                            width: 2,
                          ),
                          image: _receiptImage != null 
                              ? DecorationImage(image: FileImage(_receiptImage!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: _receiptImage == null 
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(LucideIcons.uploadCloud, color: AppColors.accentYellow, size: 40),
                                  SizedBox(height: 12),
                                  Text("Tap to upload screenshot", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              )
                            : Container(
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.all(12),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(LucideIcons.edit2, color: Colors.white, size: 16),
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    
                    const Text("NOTES (OPTIONAL)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: TextField(
                        controller: _noteController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: "Add any notes...",
                          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isUploading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.backgroundPrimary, strokeWidth: 2))
                      : const Text("CONFIRM PAYMENT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ تحديث دالة بناء طريقة الدفع لإضافة زر الرابط
  Widget _buildPaymentMethod(String title, String value, IconData icon, {String? link}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column( // تم التغيير إلى Column لاستيعاب الزر
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accentYellow, size: 24),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 6),
                    SelectableText(
                      value, 
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace')
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // ✅ إضافة زر الفتح إذا وجد الرابط
          if (link != null && link.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _launchURL(link),
                icon: const Icon(LucideIcons.externalLink, size: 14),
                label: const Text("Open in InstaPay", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentYellow,
                  side: BorderSide(color: AppColors.accentYellow.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
