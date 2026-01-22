import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // ⚠️ تم استبدال image_picker بـ file_picker
import '../../../core/services/teacher_service.dart';
import '../../widgets/custom_text_field.dart';

// أنواع المحتوى الممكن إدارتها
enum ContentType { course, subject, chapter, video, pdf }

class ManageContentScreen extends StatefulWidget {
  final ContentType contentType;
  final String? parentId; // ID الأب (مثلاً ID الكورس عند إضافة مادة)
  final Map<String, dynamic>? initialData; // بيانات للتعديل (لو null يبقى إضافة جديد)

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
  
  // حقول البيانات
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController(); // للكورسات
  final TextEditingController _priceController = TextEditingController(); // للكورسات
  final TextEditingController _urlController = TextEditingController(); // للفيديو
  
  // متغيرات الملفات (للـ PDF فقط)
  File? _selectedFile;
  String? _selectedFileName;
  String? _uploadedFileUrl; // لتخزين رابط الملف الموجود سابقاً أو بعد الرفع
  bool _isLoading = false;

  bool get isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    // ملء البيانات في حالة التعديل
    if (isEditing) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _descController.text = widget.initialData!['description'] ?? '';
      _priceController.text = widget.initialData!['price']?.toString() ?? '';
      
      // للفيديو
      if (widget.contentType == ContentType.video) {
         _urlController.text = widget.initialData!['youtube_video_id'] ?? ''; 
      }
      // للـ PDF
      if (widget.contentType == ContentType.pdf) {
        _uploadedFileUrl = widget.initialData!['file_url'];
        if (_uploadedFileUrl != null) {
          _selectedFileName = "ملف PDF الحالي";
        }
      }
    }
  }

  // دالة اختيار ملف PDF فقط
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

  // دالة الإرسال والحفظ
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // التحقق من اختيار ملف في حالة الـ PDF الجديد
    if (widget.contentType == ContentType.pdf && !isEditing && _selectedFile == null) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("يرجى اختيار ملف PDF"), backgroundColor: Colors.red),
       );
       return;
    }

    setState(() => _isLoading = true);

    try {
      String? finalFileUrl = _uploadedFileUrl;

      // 1. رفع الملف الجديد إذا تم اختياره (فقط للـ PDF)
      if (widget.contentType == ContentType.pdf && _selectedFile != null) {
        finalFileUrl = await _teacherService.uploadFile(_selectedFile!);
      }

      // 2. تجهيز البيانات حسب النوع
      Map<String, dynamic> data = {
        'title': _titleController.text,
      };

      if (isEditing) {
        data['id'] = widget.initialData!['id'];
      }

      // إضافة الحقول الخاصة بكل نوع
      switch (widget.contentType) {
        case ContentType.course:
          data['description'] = _descController.text;
          data['price'] = double.tryParse(_priceController.text) ?? 0;
          // ⚠️ تم إزالة image_url من هنا
          break;
          
        case ContentType.subject:
          data['course_id'] = widget.parentId;
          break;
          
        case ContentType.chapter:
          data['subject_id'] = widget.parentId;
          break;
          
        case ContentType.video:
          data['chapter_id'] = widget.parentId;
          data['youtube_video_id'] = _urlController.text;
          data['is_free'] = false; 
          break;
          
        case ContentType.pdf:
          data['chapter_id'] = widget.parentId;
          if (finalFileUrl != null) data['file_url'] = finalFileUrl;
          break;
      }

      // 3. تحديد نوع الجدول في قاعدة البيانات
      String dbType = '';
      switch (widget.contentType) {
        case ContentType.course: dbType = 'courses'; break;
        case ContentType.subject: dbType = 'subjects'; break;
        case ContentType.chapter: dbType = 'chapters'; break;
        case ContentType.video: dbType = 'videos'; break;
        case ContentType.pdf: dbType = 'pdfs'; break;
      }

      // 4. إرسال للباك إند
      await _teacherService.manageContent(
        action: isEditing ? 'update' : 'create',
        type: dbType,
        data: data,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? "تم التعديل بنجاح" : "تمت الإضافة بنجاح"), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // الرجوع وتحديث الصفحة السابقة
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ: ${e.toString().replaceAll('Exception:', '')}"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String titleText = '';
    switch (widget.contentType) {
      case ContentType.course: titleText = isEditing ? "تعديل الكورس" : "إضافة كورس جديد"; break;
      case ContentType.subject: titleText = isEditing ? "تعديل المادة" : "إضافة مادة جديدة"; break;
      case ContentType.chapter: titleText = isEditing ? "تعديل الفصل" : "إضافة فصل جديد"; break;
      case ContentType.video: titleText = isEditing ? "تعديل الفيديو" : "إضافة فيديو جديد"; break;
      case ContentType.pdf: titleText = isEditing ? "تعديل الملف" : "إضافة ملف PDF"; break;
    }

    return Scaffold(
      appBar: AppBar(title: Text(titleText)),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  
                  // ⚠️ تم إزالة قسم اختيار صورة الكورس من هنا تماماً

                  // --- الحقول المشتركة ---
                  CustomTextField(
                    controller: _titleController,
                    hintText: "العنوان / الاسم",
                    prefixIcon: Icons.title,
                    validator: (val) => val!.isEmpty ? "هذا الحقل مطلوب" : null,
                  ),
                  const SizedBox(height: 15),

                  // --- حقول الكورس ---
                  if (widget.contentType == ContentType.course) ...[
                    CustomTextField(
                      controller: _descController,
                      hintText: "وصف الكورس",
                      prefixIcon: Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 15),
                    CustomTextField(
                      controller: _priceController,
                      hintText: "السعر (EGP)",
                      prefixIcon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                    ),
                  ],

                  // --- حقول الفيديو ---
                  if (widget.contentType == ContentType.video) ...[
                    CustomTextField(
                      controller: _urlController,
                      hintText: "رابط يوتيوب (ID)",
                      prefixIcon: Icons.video_library,
                    ),
                    const SizedBox(height: 5),
                    const Text("مثال: إذا كان الرابط youtube.com/watch?v=xyz123 ضع فقط xyz123", 
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],

                  // --- حقول PDF (تظهر فقط عند اختيار PDF) ---
                  if (widget.contentType == ContentType.pdf) ...[
                     const SizedBox(height: 10),
                     ListTile(
                       contentPadding: EdgeInsets.zero,
                       leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 30),
                       title: Text(
                         _selectedFileName ?? "لم يتم اختيار ملف بعد",
                         style: TextStyle(
                           color: _selectedFileName == null ? Colors.grey : Colors.black,
                           fontWeight: _selectedFileName == null ? FontWeight.normal : FontWeight.bold
                         ),
                       ),
                       subtitle: const Text("اضغط لاختيار ملف PDF من جهازك"),
                       trailing: ElevatedButton.icon(
                         onPressed: _pickPdfFile,
                         icon: const Icon(Icons.upload_file),
                         label: const Text("اختيار ملف"),
                         style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.blue[50],
                           foregroundColor: Colors.blue,
                           elevation: 0
                         ),
                       ),
                       onTap: _pickPdfFile,
                     ),
                     const Divider(),
                  ],

                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.blue[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      isEditing ? "حفظ التعديلات" : "إضافة",
                      style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
