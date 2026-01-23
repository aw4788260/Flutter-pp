import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ لاستخدام الحافظة (Clipboard)
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../../core/constants/app_colors.dart';
import 'main_wrapper.dart'; 
import '../../core/services/storage_service.dart';

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

  // ✅ دالة لنسخ النص إلى الحافظة
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Copied to clipboard"), 
        backgroundColor: AppColors.success, 
        duration: Duration(seconds: 1)
      ),
    );
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
      var box = await StorageService.openBox('auth_box');
      final token = box.get('jwt_token');
      final deviceId = box.get('device_id');

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
            'Authorization': 'Bearer $token',
            'x-device-id': deviceId,
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
    // ✅ استخراج القوائم من الـ paymentInfo
    // نستخدم List<dynamic> أو List<String> مع التحقق من null
    final List cashNumbers = (widget.paymentInfo['cash_numbers'] as List?) ?? [];
    final List instapayNumbers = (widget.paymentInfo['instapay_numbers'] as List?) ?? [];
    final List instapayLinks = (widget.paymentInfo['instapay_links'] as List?) ?? [];

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                    // Amount Box
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

                    // 1. Cash Numbers Section
                    if (cashNumbers.isNotEmpty) ...[
                      const Text("CASH WALLETS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      ...cashNumbers.map((num) => _buildCopyableCard("WALLET NUMBER", num.toString(), Icons.account_balance_wallet)),
                      const SizedBox(height: 24),
                    ],

                    // 2. InstaPay Numbers Section
                    if (instapayNumbers.isNotEmpty) ...[
                      const Text("INSTAPAY NUMBERS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      ...instapayNumbers.map((num) => _buildCopyableCard("INSTAPAY PHONE", num.toString(), Icons.phone_iphone)),
                      const SizedBox(height: 24),
                    ],

                    // 3. InstaPay Links Section
                    if (instapayLinks.isNotEmpty) ...[
                      const Text("INSTAPAY LINKS / USERNAME", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      ...instapayLinks.map((link) => _buildLinkCard(link.toString())),
                      const SizedBox(height: 24),
                    ],

                    // Receipt Upload
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
                    
                    // Notes
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

            // Confirm Button
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

  // ✅ ويدجت للأرقام مع زر نسخ
  Widget _buildCopyableCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.accentYellow, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 4),
                SelectableText(
                  value, 
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 18, color: AppColors.textSecondary),
            onPressed: () => _copyToClipboard(value),
            tooltip: "Copy",
          )
        ],
      ),
    );
  }

  // ✅ ويدجت للروابط مع زر فتح وزر نسخ
  Widget _buildLinkCard(String link) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.link, color: AppColors.accentYellow, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  link,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 18, color: AppColors.textSecondary),
                onPressed: () => _copyToClipboard(link),
              )
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _launchURL(link.startsWith('http') ? link : 'https://$link'),
              icon: const Icon(LucideIcons.externalLink, size: 14),
              label: const Text("Open Link / InstaPay", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentYellow,
                side: BorderSide(color: AppColors.accentYellow.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
