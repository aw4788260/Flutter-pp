import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/teacher_service.dart';
import '../../widgets/custom_text_field.dart';

class CreateExamScreen extends StatefulWidget {
  final String subjectId; // معرف المادة
  final String? examId;   // ✅ معرف الامتحان (اختياري - للتعديل)

  const CreateExamScreen({Key? key, required this.subjectId, this.examId}) : super(key: key);

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _formKey = GlobalKey<FormState>();
  final TeacherService _teacherService = TeacherService();

  // بيانات الامتحان الأساسية
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  
  bool _randomizeQuestions = true; 
  DateTime? _startDate; 
  DateTime? _endDate;   
  
  List<QuestionModel> _questions = [];
  bool _isSubmitting = false;
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    if (widget.examId != null) {
      _loadExamDetails();
    }
  }

  // --- جلب تفاصيل الامتحان للتعديل ---
  Future<void> _loadExamDetails() async {
    setState(() => _isLoadingDetails = true);
    try {
      final data = await _teacherService.getExamDetails(widget.examId!);
      
      setState(() {
        _titleController.text = data['title'] ?? '';
        _durationController.text = (data['duration_minutes'] ?? 0).toString();
        _randomizeQuestions = data['randomize_questions'] ?? true;
        
        if (data['start_time'] != null) {
          _startDate = DateTime.parse(data['start_time']).toLocal();
        }
        if (data['end_time'] != null) {
          _endDate = DateTime.parse(data['end_time']).toLocal();
        }

        if (data['questions'] != null) {
          _questions = (data['questions'] as List).map((q) {
            int correctIndex = 0;
            List<String> options = [];
            
            if (q['options'] != null) {
              var sortedOptions = List.from(q['options']);
              sortedOptions.sort((a, b) => (a['sort_order'] ?? 0).compareTo(b['sort_order'] ?? 0));

              for (int i = 0; i < sortedOptions.length; i++) {
                var opt = sortedOptions[i];
                options.add(opt['option_text']);
                if (opt['is_correct'] == true) {
                  correctIndex = i;
                }
              }
            }

            return QuestionModel(
              text: q['question_text'],
              options: options,
              correctOptionIndex: correctIndex,
              imageUrl: q['image_file_id'],
            );
          }).toList();
        }
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل تحميل بيانات الامتحان: $e"), backgroundColor: Colors.red));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  // --- دوال اختيار الوقت والتاريخ ---
  Future<void> _pickDateTime(bool isStart) async {
    final now = DateTime.now();
    final initialDate = isStart 
        ? (_startDate ?? now) 
        : (_endDate ?? now);

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2023),
      lastDate: now.add(const Duration(days: 365)),
    );
    
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
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
      List<Map<String, dynamic>> processedQuestions = [];
      
      for (var q in _questions) {
        String? imageUrl = q.imageUrl;
        
        if (q.imageFile != null) {
          imageUrl = await _teacherService.uploadFile(q.imageFile!);
        }

        processedQuestions.add({
          'text': q.text,
          'options': q.options,
          'correctIndex': q.correctOptionIndex,
          'image': imageUrl, 
        });
      }

      final examData = {
        'title': _titleController.text,
        'subjectId': widget.subjectId,
        'duration': int.parse(_durationController.text),
        'randomize': _randomizeQuestions,
        'start_time': _startDate!.toIso8601String(), 
        'end_time': _endDate!.toIso8601String(),
        'questions': processedQuestions,
      };

      if (widget.examId != null) {
        examData['examId'] = widget.examId!;
      }

      await _teacherService.createExam(examData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.examId != null ? "تم تحديث الامتحان بنجاح" : "تم إنشاء الامتحان بنجاح"), 
            backgroundColor: Colors.green
          )
        );
        Navigator.pop(context, true);
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
    if (_isLoadingDetails) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examId != null ? "تعديل الامتحان" : "إنشاء امتحان جديد"),
      ),
      body: _isSubmitting
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text("جاري رفع الصور وحفظ البيانات...")
              ],
            ))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CustomTextField(
                    label: "عنوان الامتحان",
                    controller: _titleController,
                    hintText: "مثال: امتحان شامل الفصل الأول",
                    prefixIcon: Icons.quiz,
                    validator: (val) => val!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 15),
                  
                  CustomTextField(
                    label: "المدة (دقائق)",
                    controller: _durationController,
                    hintText: "أدخل مدة الامتحان",
                    prefixIcon: Icons.timer,
                    keyboardType: TextInputType.number,
                    validator: (val) => val!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 15),

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
                            subtitle: Text("${q.options.length} اختيارات • ${q.imageFile != null ? "صورة جديدة" : (q.imageUrl != null ? "صورة محفوظة" : "نص فقط")}"),
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
                    child: Text(
                      widget.examId != null ? "حفظ التعديلات" : "حفظ ونشر الامتحان", 
                      style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)
                    ),
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
// 🧩 مودل السؤال
// ==========================================================
class QuestionModel {
  String text;
  List<String> options;
  int correctOptionIndex;
  File? imageFile;
  String? imageUrl;

  QuestionModel({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
    this.imageFile,
    this.imageUrl,
  });
}

// ==========================================================
// 💬 نافذة إضافة/تعديل السؤال (ديناميكية)
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
  
  // ✅ تغيير: القائمة أصبحت ديناميكية
  List<TextEditingController> _optionControllers = [];
  
  int _correctIndex = 0;
  File? _selectedImage;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion != null) {
      _questionTextController.text = widget.initialQuestion!.text;
      
      // تعبئة الخيارات الموجودة
      for (var option in widget.initialQuestion!.options) {
        _optionControllers.add(TextEditingController(text: option));
      }
      
      _correctIndex = widget.initialQuestion!.correctOptionIndex;
      _selectedImage = widget.initialQuestion!.imageFile;
      _existingImageUrl = widget.initialQuestion!.imageUrl;
    } else {
      // ✅ الحالة الافتراضية: 4 خيارات فارغة (ويمكن للمستخدم التعديل)
      _optionControllers = List.generate(4, (_) => TextEditingController());
    }
  }

  @override
  void dispose() {
    _questionTextController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image, 
    );

    if (result != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
      });
    }
  }

  // ✅ دالة إضافة خيار جديد
  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  // ✅ دالة حذف خيار
  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يجب أن يحتوي السؤال على خيارين على الأقل"))
      );
      return;
    }

    setState(() {
      _optionControllers[index].dispose(); // تحرير الموارد
      _optionControllers.removeAt(index);
      
      // تعديل الإجابة الصحيحة إذا تأثرت بالحذف
      if (_correctIndex == index) {
        _correctIndex = 0; // إعادة تعيين للأول بشكل افتراضي
      } else if (_correctIndex > index) {
        _correctIndex--; // تقليل المؤشر لأن القائمة انزاحت
      }
    });
  }

  void _save() {
    if (!_qFormKey.currentState!.validate()) return;

    List<String> options = _optionControllers.map((c) => c.text.trim()).toList();
    
    // التأكد من عدم وجود خيارات فارغة
    if (options.any((o) => o.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى ملء جميع حقول الخيارات أو حذف الفارغ منها"))
      );
      return;
    }

    // التأكد من أن مؤشر الإجابة الصحيحة صالح
    if (_correctIndex >= options.length) {
      _correctIndex = 0;
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

                // 2. صورة السؤال
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedImage != null 
                            ? "تم اختيار صورة جديدة" 
                            : (_existingImageUrl != null ? "صورة محفوظة مسبقاً" : "لا توجد صورة"),
                        style: TextStyle(
                          color: _selectedImage != null ? Colors.green : Colors.grey,
                          fontWeight: _selectedImage != null ? FontWeight.bold : FontWeight.normal
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      tooltip: "رفع/تغيير صورة",
                    ),
                    if (_selectedImage != null || _existingImageUrl != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: "حذف الصورة",
                        onPressed: () => setState(() {
                          _selectedImage = null;
                          _existingImageUrl = null;
                        }),
                      )
                  ],
                ),
                const Divider(),

                // 3. الخيارات الديناميكية
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("الخيارات (حدد الصحيحة):", style: TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _addOption,
                      icon: const Icon(Icons.add_circle, size: 18),
                      label: const Text("إضافة خيار"),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                
                // قائمة الخيارات
                ...List.generate(_optionControllers.length, (index) {
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
                        if (_optionControllers.length > 2) // إظهار زر الحذف فقط إذا كان هناك أكثر من خيارين
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () => _removeOption(index),
                            tooltip: "حذف الخيار",
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
