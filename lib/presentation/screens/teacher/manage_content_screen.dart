import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/services/storage_service.dart'; // ✅ إضافة: استيراد خدمة التخزين
import '../../widgets/custom_text_field.dart';
import '../../../core/constants/app_colors.dart';

enum ContentType { course, subject, chapter, video, pdf }

class ManageContentScreen extends StatefulWidget {
  final ContentType contentType;
  final String? parentId;
  final Map<String, dynamic>? initialData;

  const ManageContentScreen({
    Key? key,
    required this.contentType,
    this.parentId,
    this.initialData,
  }) : super(key: key);

  @override
  State<ManageContentScreen> createState() => _ManageContentScreenState();
}

class _ManageContentScreenState extends State<ManageContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final TeacherService _teacherService = TeacherService();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  File? _selectedFile;
  String? _selectedFileName;
  String? _uploadedFileUrl;
  bool _isLoading = false;

  bool get isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _descController.text = widget.initialData!['description'] ?? '';
      _priceController.text = widget.initialData!['price']?.toString() ?? '';

      if (widget.contentType == ContentType.video) {
        _urlController.text = widget.initialData!['youtube_video_id'] ?? '';
      }
      if (widget.contentType == ContentType.pdf) {
        _uploadedFileUrl = widget.initialData!['file_url'];
        if (_uploadedFileUrl != null) {
          _selectedFileName = "Current PDF File";
        }
      }
    }
  }

  Future<void> _pickPdfFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _selectedFileName = result.files.single.name;
      });
    }
  }

  // ✅ دالة لاستخراج ID الفيديو من الرابط
  String? _extractYoutubeId(String url) {
    if (url.length == 11 && !url.contains('.')) return url; // هو أصلاً ID
    
    RegExp regExp = RegExp(
      r'.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|shorts\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url)?.group(1);
    return (match != null && match.length >= 11) ? match : null;
  }

  // ✅ إضافة: دالة لتحديث الكاش المحلي في Hive
  Future<void> _updateLocalCache() async {
    try {
      // 1. جلب البيانات المحدثة بالكامل من السيرفر
      final updatedContent = await _teacherService.getMyContent();
      
      // 2. فتح الصندوق وتحديث البيانات
      // ملاحظة: تأكد أن الاسم 'teacher_data' ومفتاح 'my_content' يطابق المستخدم في شاشة العرض
      var box = await StorageService.openBox('teacher_data');
      await box.put('my_content', updatedContent);
      
      debugPrint("✅ Cache updated successfully in Hive");
    } catch (e) {
      debugPrint("⚠️ Failed to update local cache: $e");
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.contentType == ContentType.pdf && !isEditing && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a PDF file"), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? finalFileUrl = _uploadedFileUrl;

      if (widget.contentType == ContentType.pdf && _selectedFile != null) {
        finalFileUrl = await _teacherService.uploadFile(_selectedFile!);
      }

      Map<String, dynamic> data = {
        'title': _titleController.text,
      };

      if (isEditing) {
        data['id'] = widget.initialData!['id'];
      }

      switch (widget.contentType) {
        case ContentType.course:
          data['description'] = _descController.text;
          data['price'] = double.tryParse(_priceController.text) ?? 0;
          break;
        case ContentType.subject:
          data['course_id'] = widget.parentId;
          data['price'] = double.tryParse(_priceController.text) ?? 0;
          break;
        case ContentType.chapter:
          data['subject_id'] = widget.parentId;
          break;
        case ContentType.video:
          data['chapter_id'] = widget.parentId;
          
          String? videoId = _extractYoutubeId(_urlController.text);
          if (videoId == null) {
            throw Exception("رابط الفيديو غير صحيح");
          }
          data['youtube_video_id'] = videoId;
          break;
        case ContentType.pdf:
          data['chapter_id'] = widget.parentId;
          if (finalFileUrl != null) data['file_url'] = finalFileUrl;
          break;
      }

      String dbType = '';
      switch (widget.contentType) {
        case ContentType.course: dbType = 'courses'; break;
        case ContentType.subject: dbType = 'subjects'; break;
        case ContentType.chapter: dbType = 'chapters'; break;
        case ContentType.video: dbType = 'videos'; break;
        case ContentType.pdf: dbType = 'pdfs'; break;
      }

      // 1. تنفيذ العملية في السيرفر
      await _teacherService.manageContent(
        action: isEditing ? 'update' : 'create',
        type: dbType,
        data: data,
      );

      // 2. ✅ تحديث الكاش المحلي فوراً
      await _updateLocalCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? "Updated Successfully" : "Created Successfully"), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString().replaceAll('Exception:', '')}"), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteItem() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text("Confirm Delete", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to delete this item? This cannot be undone.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      String dbType = '';
      switch (widget.contentType) {
        case ContentType.course: dbType = 'courses'; break;
        case ContentType.subject: dbType = 'subjects'; break;
        case ContentType.chapter: dbType = 'chapters'; break;
        case ContentType.video: dbType = 'videos'; break;
        case ContentType.pdf: dbType = 'pdfs'; break;
      }

      // 1. حذف العنصر في السيرفر
      await _teacherService.manageContent(
        action: 'delete',
        type: dbType,
        data: {'id': widget.initialData!['id']},
      );

      // 2. ✅ تحديث الكاش المحلي فوراً
      await _updateLocalCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted Successfully"), backgroundColor: AppColors.success));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete Failed: $e"), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String titleText = '';
    switch (widget.contentType) {
      case ContentType.course: titleText = isEditing ? "Edit Course" : "New Course"; break;
      case ContentType.subject: titleText = isEditing ? "Edit Subject" : "New Subject"; break;
      case ContentType.chapter: titleText = isEditing ? "Edit Chapter" : "New Chapter"; break;
      case ContentType.video: titleText = isEditing ? "Edit Video" : "New Video"; break;
      case ContentType.pdf: titleText = isEditing ? "Edit PDF" : "New PDF"; break;
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(titleText, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        leading: const BackButton(color: AppColors.accentYellow),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: "Delete",
              onPressed: _isLoading ? null : _deleteItem,
            ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // --- الحقول المشتركة (العنوان) ---
                  CustomTextField(
                    label: "Title / Name",
                    controller: _titleController,
                    hintText: "Enter title here",
                    prefixIcon: Icons.title,
                    validator: (val) => val!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 16),

                  // ✅ الوصف يظهر فقط للكورس
                  if (widget.contentType == ContentType.course) ...[
                    CustomTextField(
                      label: "Description",
                      controller: _descController,
                      hintText: "Enter description",
                      prefixIcon: Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ✅ السعر يظهر للكورس والمادة (مشترك)
                  if (widget.contentType == ContentType.course || widget.contentType == ContentType.subject) ...[
                    CustomTextField(
                      label: "Price (EGP)",
                      controller: _priceController,
                      hintText: "0.0",
                      prefixIcon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // --- حقول الفيديو ---
                  if (widget.contentType == ContentType.video) ...[
                    CustomTextField(
                      label: "YouTube Video Link",
                      controller: _urlController,
                      hintText: "https://youtu.be/...",
                      prefixIcon: Icons.video_library,
                    ),
                    const SizedBox(height: 8),
                    Text("Paste the full YouTube link or just the ID",
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.6))),
                  ],

                  // --- حقول PDF ---
                  if (widget.contentType == ContentType.pdf) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.picture_as_pdf, color: AppColors.accentOrange, size: 30),
                        title: Text(
                          _selectedFileName ?? "No file selected",
                          style: TextStyle(
                            color: _selectedFileName == null ? Colors.grey : Colors.white,
                            fontWeight: _selectedFileName == null ? FontWeight.normal : FontWeight.bold,
                            fontSize: 14
                          ),
                        ),
                        subtitle: const Text("Tap to select PDF", style: TextStyle(color: Colors.grey, fontSize: 11)),
                        trailing: const Icon(Icons.upload_file, color: AppColors.accentYellow),
                        onTap: _pickPdfFile,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 32),

                  // زر الحفظ
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: AppColors.backgroundPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      isEditing ? "SAVE CHANGES" : "CREATE",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                  ),

                  // زر حذف إضافي
                  if (isEditing) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _deleteItem,
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      label: const Text("DELETE PERMANENTLY", style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}
