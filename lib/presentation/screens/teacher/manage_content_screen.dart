import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  
  File? _selectedImage;
  bool _isLoading = false;
  String? _uploadedImageUrl; // لتخزين رابط الصورة بعد الرفع

  bool get isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    // ملء البيانات في حالة التعديل
    if (isEditing) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _descController.text = widget.initialData!['description'] ?? '';
      _priceController.text = widget.initialData!['price']?.toString() ?? '';
      _uploadedImageUrl = widget.initialData!['image_url'];
      // للفيديو
      if (widget.contentType == ContentType.video) {
         // قد تحتاج لجلب الرابط من مكان معين بالبيانات
         _urlController.text = widget.initialData!['youtube_id'] ?? ''; 
      }
    }
  }

  // دالة اختيار الصورة
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  // دالة الإرسال والحفظ
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. رفع الصورة إذا وجدت
      if (_selectedImage != null) {
        _uploadedImageUrl = await _teacherService.uploadFile(_selectedImage!);
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
          if (_uploadedImageUrl != null) data['image_url'] = _uploadedImageUrl;
          break;
          
        case ContentType.subject:
          data['course_id'] = widget.parentId;
          break;
          
        case ContentType.chapter:
          data['subject_id'] = widget.parentId;
          break;
          
        case ContentType.video:
          data['chapter_id'] = widget.parentId;
          data['youtube_video_id'] = _urlController.text; // أو الرابط المباشر
          data['is_free'] = false; // يمكن إضافة Checkbox
          break;
          
        case ContentType.pdf:
          data['chapter_id'] = widget.parentId;
          if (_uploadedImageUrl != null) data['file_url'] = _uploadedImageUrl; // نستخدم نفس المتغير للملف
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
          SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: Colors.red),
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
                  // --- الصورة (للكورس فقط حالياً) ---
                  if (widget.contentType == ContentType.course) ...[
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey),
                          image: _selectedImage != null 
                              ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                              : (_uploadedImageUrl != null 
                                  ? DecorationImage(image: NetworkImage(_uploadedImageUrl!), fit: BoxFit.cover) 
                                  : null),
                        ),
                        child: _selectedImage == null && _uploadedImageUrl == null
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                                  Text("اضغط لاختيار صورة الغلاف", style: TextStyle(color: Colors.grey)),
                                ],
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

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

                  // --- حقول PDF ---
                  if (widget.contentType == ContentType.pdf) ...[
                     ElevatedButton.icon(
                       onPressed: _pickImage, // هنا نستخدم نفس دالة الرفع تجاوزاً، يفضل استخدام FilePicker للملفات
                       icon: const Icon(Icons.upload_file),
                       label: Text(_selectedImage == null ? "رفع ملف PDF" : "تم اختيار الملف"),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.orange,
                         foregroundColor: Colors.white,
                       ),
                     ),
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
