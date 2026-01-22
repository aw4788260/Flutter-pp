import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/teacher_service.dart';
import '../../widgets/custom_text_field.dart';

class CreateExamScreen extends StatefulWidget {
  final String subjectId; // معرف المادة التي سيضاف لها الامتحان

  const CreateExamScreen({Key? key, required this.subjectId}) : super(key: key);

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _formKey = GlobalKey<FormState>();
  final TeacherService _teacherService = TeacherService();

  // بيانات الامتحان الأساسية
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  
  bool _randomizeQuestions = true; // هل الأسئلة عشوائية؟
  DateTime? _startDate; // تاريخ التفعيل
  DateTime? _endDate;   // تاريخ الإغلاق
  
  List<QuestionModel> _questions = [];
  bool _isSubmitting = false;

  // --- دوال اختيار الوقت والتاريخ ---
  Future<void> _pickDateTime(bool isStart) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null) return;

    final dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    
    setState(() {
      if (isStart) {
        _startDate = dateTime;
      } else {
        _endDate = dateTime;
      }
    });
  }

  // --- دالة إضافة/تعديل سؤال ---
  void _openQuestionDialog({QuestionModel? existingQuestion, int? index}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuestionDialog(
        initialQuestion: existingQuestion,
        onSave: (question) {
          setState(() {
            if (index != null) {
              _questions[index] = question;
            } else {
              _questions.add(question);
            }
          });
        },
      ),
    );
  }

  // --- الحفظ والإرسال ---
  Future<void> _submitExam() async {
    if (!_formKey.currentState!.validate()) return;
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يجب إضافة سؤال واحد على الأقل"), backgroundColor: Colors.red));
      return;
    }
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى تحديد وقت بداية ونهاية الامتحان"), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. رفع الصور الخاصة بالأسئلة (إن وجدت)
      List<Map<String, dynamic>> processedQuestions = [];
      
      for (var q in _questions) {
        String? imageUrl = q.imageUrl;
        
        // إذا كان هناك ملف صورة لم يُرفع بعد
        if (q.imageFile != null) {
          imageUrl = await _teacherService.uploadFile(q.imageFile!);
        }

        processedQuestions.add({
          'text': q.text,
          'options': q.options,
          'correctIndex': q.correctOptionIndex,
          'image': imageUrl, // نرسل الرابط للباك إند
        });
      }

      // 2. تجهيز بيانات الامتحان
      final examData = {
        'title': _titleController.text,
        'subjectId': widget.subjectId,
        'duration': int.parse(_durationController.text),
        'randomize': _randomizeQuestions,
        'activation_date': _startDate!.toIso8601String(),
        'closing_date': _endDate!.toIso8601String(),
        'questions': processedQuestions,
      };

      // 3. الإرسال للسيرفر
      await _teacherService.createExam(examData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إنشاء الامتحان بنجاح"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إنشاء امتحان جديد")),
      body: _isSubmitting
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text("جاري رفع الصور وحفظ الامتحان...")
              ],
            ))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- البيانات الأساسية ---
                  CustomTextField(
                    controller: _titleController,
                    hintText: "عنوان الامتحان (مثال: امتحان شامل الفصل الأول)",
                    prefixIcon: Icons.quiz,
                    validator: (val) => val!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 15),
                  CustomTextField(
                    controller: _durationController,
                    hintText: "مدة الامتحان (بالدقائق)",
                    prefixIcon: Icons.timer,
                    keyboardType: TextInputType.number,
                    validator: (val) => val!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 15),

                  // --- التواريخ والعشوائية ---
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text("ترتيب أسئلة عشوائي للطلاب"),
                          subtitle: const Text("يظهر لكل طالب ترتيب مختلف"),
                          value: _randomizeQuestions,
                          onChanged: (val) => setState(() => _randomizeQuestions = val),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.calendar_today, color: Colors.blue),
                          title: Text(_startDate == null ? "تاريخ ووقت التفعيل (البداية)" : "يبدأ: ${_formatDate(_startDate!)}"),
                          onTap: () => _pickDateTime(true),
                        ),
                        ListTile(
                          leading: const Icon(Icons.event_busy, color: Colors.red),
                          title: Text(_endDate == null ? "تاريخ ووقت الإغلاق (النهاية)" : "ينتهي: ${_formatDate(_endDate!)}"),
                          onTap: () => _pickDateTime(false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- قسم الأسئلة ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("الأسئلة (${_questions.length})", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        onPressed: () => _openQuestionDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text("إضافة سؤال"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_questions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text("لم تتم إضافة أسئلة بعد", style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        final q = _questions[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(child: Text("${index + 1}")),
                            title: Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(q.imageFile != null ? "يحتوي على صورة" : "نص فقط"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => setState(() => _questions.removeAt(index)),
                            ),
                            onTap: () => _openQuestionDialog(existingQuestion: q, index: index),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _submitExam,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.blue[800],
                    ),
                    child: const Text("حفظ ونشر الامتحان", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}";
  }
}

// ==========================================================
// 🧩 مودل السؤال (للاستخدام الداخلي في الشاشة)
// ==========================================================
class QuestionModel {
  String text;
  List<String> options;
  int correctOptionIndex;
  File? imageFile; // الصورة كملف (جديدة)
  String? imageUrl; // الصورة كرابط (إذا كانت موجودة مسبقاً)

  QuestionModel({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
    this.imageFile,
    this.imageUrl,
  });
}

// ==========================================================
// 💬 نافذة إضافة/تعديل السؤال
// ==========================================================
class QuestionDialog extends StatefulWidget {
  final QuestionModel? initialQuestion;
  final Function(QuestionModel) onSave;

  const QuestionDialog({Key? key, this.initialQuestion, required this.onSave}) : super(key: key);

  @override
  State<QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<QuestionDialog> {
  final _qFormKey = GlobalKey<FormState>();
  final TextEditingController _questionTextController = TextEditingController();
  final List<TextEditingController> _optionControllers = List.generate(4, (_) => TextEditingController());
  
  int _correctIndex = 0;
  File? _selectedImage;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion != null) {
      _questionTextController.text = widget.initialQuestion!.text;
      for (int i = 0; i < 4; i++) {
        if (i < widget.initialQuestion!.options.length) {
          _optionControllers[i].text = widget.initialQuestion!.options[i];
        }
      }
      _correctIndex = widget.initialQuestion!.correctOptionIndex;
      _selectedImage = widget.initialQuestion!.imageFile;
      _existingImageUrl = widget.initialQuestion!.imageUrl;
    }
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image, // نقبل الصور فقط هنا
    );

    if (result != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
      });
    }
  }

  void _save() {
    if (!_qFormKey.currentState!.validate()) return;

    // التحقق من أن الخيارات ممتلئة
    List<String> options = _optionControllers.map((c) => c.text.trim()).toList();
    if (options.any((o) => o.isEmpty)) {
      // تنبيه بسيط
      return; 
    }

    final newQuestion = QuestionModel(
      text: _questionTextController.text,
      options: options,
      correctOptionIndex: _correctIndex,
      imageFile: _selectedImage,
      imageUrl: _existingImageUrl,
    );

    widget.onSave(newQuestion);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialQuestion == null ? "سؤال جديد" : "تعديل السؤال"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _qFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. نص السؤال
                TextFormField(
                  controller: _questionTextController,
                  decoration: const InputDecoration(labelText: "نص السؤال", border: OutlineInputBorder()),
                  maxLines: 2,
                  validator: (val) => val!.isEmpty ? "مطلوب" : null,
                ),
                const SizedBox(height: 10),

                // 2. صورة السؤال (اختياري)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedImage != null ? "تم اختيار صورة" : (_existingImageUrl != null ? "صورة محفوظة" : "لا توجد صورة"),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      label: const Text("رفع صورة"),
                    ),
                    if (_selectedImage != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => setState(() => _selectedImage = null),
                      )
                  ],
                ),
                const Divider(),

                // 3. الخيارات الأربعة
                const Align(alignment: Alignment.centerRight, child: Text("الخيارات (حدد الإجابة الصحيحة):")),
                const SizedBox(height: 5),
                ...List.generate(4, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Radio<int>(
                          value: index,
                          groupValue: _correctIndex,
                          onChanged: (val) => setState(() => _correctIndex = val!),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _optionControllers[index],
                            decoration: InputDecoration(
                              labelText: "الخيار ${index + 1}",
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (val) => val!.isEmpty ? "مطلوب" : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(onPressed: _save, child: const Text("حفظ السؤال")),
      ],
    );
  }
}
