import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';
// تأكد من مسار ملف الألوان، أو احذفه إذا لم يكن مستخدماً في مشروعك
import '../../../core/constants/app_colors.dart';

class ManageStudentsScreen extends StatefulWidget {
  const ManageStudentsScreen({Key? key}) : super(key: key);

  @override
  State<ManageStudentsScreen> createState() => _ManageStudentsScreenState();
}

class _ManageStudentsScreenState extends State<ManageStudentsScreen> {
  final TeacherService _teacherService = TeacherService();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = false;
  Map<String, dynamic>? _studentData; // بيانات الطالب
  List<dynamic> _accessList = []; // قائمة الصلاحيات الحالية
  
  // لتخزين محتوى المعلم (الكورسات والمواد) لاستخدامه في القوائم
  List<dynamic> _myContent = [];

  @override
  void initState() {
    super.initState();
    _fetchMyContent();
  }

  // جلب كورسات ومواد المعلم مرة واحدة عند الفتح
  Future<void> _fetchMyContent() async {
    try {
      final data = await _teacherService.getMyContent();
      if (mounted) {
        setState(() {
          _myContent = data;
        });
      }
    } catch (e) {
      debugPrint("Error fetching content: $e");
    }
  }

  // دالة البحث
  Future<void> _search() async {
    if (_searchController.text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل 3 أرقام/حروف على الأقل")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _studentData = null;
      _accessList = [];
    });

    try {
      final result = await _teacherService.searchStudent(_searchController.text.trim());
      setState(() {
        _studentData = result['student'];
        _accessList = result['access'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("لم يتم العثور على الطالب أو حدث خطأ: $e"), backgroundColor: Colors.orange),
      );
    }
  }

  // دالة سحب أو منح الصلاحية (فردي)
  Future<void> _toggleAccess(String type, String itemId, bool allow) async {
    if (_studentData == null) return;

    // تأكيد الحذف
    if (!allow) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("سحب الصلاحية"),
          content: const Text("هل أنت متأكد من حذف الصلاحية؟ سيتم منع الطالب من الوصول لهذا المحتوى."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("تأكيد السحب"),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isLoading = true);

    try {
      await _teacherService.toggleAccess(
        _studentData!['id'].toString(), // التأكد من تحويل المعرف لنص
        type, 
        itemId, 
        allow
      );

      // إعادة تحديث البيانات لرؤية التغييرات
      await _search(); 
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allow ? "تمت إضافة الصلاحية بنجاح" : "تم سحب الصلاحية بنجاح"),
            backgroundColor: allow ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("فشلت العملية: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // دالة المنح الجماعي
  Future<void> _grantBulkAccess(Set<String> courses, Set<String> subjects) async {
    if (_studentData == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      int successCount = 0;

      // منح الكورسات
      for (var courseId in courses) {
        await _teacherService.toggleAccess(_studentData!['id'].toString(), 'course', courseId, true);
        successCount++;
      }

      // منح المواد
      for (var subjectId in subjects) {
        await _teacherService.toggleAccess(_studentData!['id'].toString(), 'subject', subjectId, true);
        successCount++;
      }

      await _search();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم منح $successCount صلاحيات بنجاح"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ أثناء المنح: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ✅ النافذة الجديدة: عرض شجري مع Checkboxes
  void _showAddAccessDialog() {
    // التأكد من تحميل البيانات أولاً
    if (_myContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("جارِ تحميل بيانات الكورسات... حاول مرة أخرى بعد قليل."))
      );
      _fetchMyContent();
      return;
    }

    // 1. تحديد المعرفات التي يمتلكها الطالب بالفعل لاستبعادها
    final Set<String> ownedCourseIds = _accessList
        .where((e) => e['type'] == 'course')
        .map((e) => e['id'].toString())
        .toSet();

    final Set<String> ownedSubjectIds = _accessList
        .where((e) => e['type'] == 'subject')
        .map((e) => e['id'].toString())
        .toSet();

    // مجموعات لتخزين الاختيارات الجديدة
    Set<String> selectedCourses = {};
    Set<String> selectedSubjects = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("اختر الصلاحيات لمنحها"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _myContent.length,
                itemBuilder: (context, index) {
                  final course = _myContent[index];
                  final String courseId = course['id'].toString();
                  
                  // إذا كان الطالب يمتلك الكورس بالفعل، لا نعرضه نهائياً في القائمة
                  if (ownedCourseIds.contains(courseId)) {
                    return const SizedBox.shrink();
                  }

                  // تصفية المواد داخل الكورس: نعرض فقط المواد التي لا يملكها الطالب
                  final List subjects = (course['subjects'] as List? ?? [])
                      .where((s) => !ownedSubjectIds.contains(s['id'].toString()))
                      .toList();

                  final bool isCourseSelected = selectedCourses.contains(courseId);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ExpansionTile(
                      // الكورس الرئيسي
                      title: Row(
                        children: [
                          Checkbox(
                            value: isCourseSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedCourses.add(courseId);
                                  // عند اختيار الكورس، نلغي اختيار أي مواد تابعة له لتجنب التكرار
                                  for (var s in subjects) {
                                    selectedSubjects.remove(s['id'].toString());
                                  }
                                } else {
                                  selectedCourses.remove(courseId);
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              course['title'], 
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      // المواد الفرعية
                      children: subjects.map<Widget>((subject) {
                        final String subjectId = subject['id'].toString();
                        final bool isSubjectSelected = selectedSubjects.contains(subjectId);

                        return Padding(
                          padding: const EdgeInsets.only(right: 40.0), // إزاحة لليمين
                          child: CheckboxListTile(
                            title: Text(subject['title']),
                            // إذا تم اختيار الكورس، تظهر المادة وكأنها مختارة (أو معطلة)
                            value: isCourseSelected ? true : isSubjectSelected,
                            // نعطل الاختيار إذا كان الكورس الرئيسي مختاراً
                            onChanged: isCourseSelected 
                                ? null 
                                : (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        selectedSubjects.add(subjectId);
                                      } else {
                                        selectedSubjects.remove(subjectId);
                                      }
                                    });
                                  },
                            activeColor: isCourseSelected ? Colors.grey : Theme.of(context).primaryColor,
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text("إلغاء")
              ),
              ElevatedButton(
                onPressed: (selectedCourses.isEmpty && selectedSubjects.isEmpty)
                    ? null // تعطيل الزر إذا لم يتم اختيار شيء
                    : () {
                        Navigator.pop(ctx);
                        _grantBulkAccess(selectedCourses, selectedSubjects);
                      },
                child: Text("منح (${selectedCourses.length + selectedSubjects.length})"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إدارة الطلاب (طلابي)")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- خانة البحث ---
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "رقم الهاتف أو اسم المستخدم",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _search,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("بحث"),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- محتوى النتائج ---
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_studentData != null)
              Expanded(
                child: ListView(
                  children: [
                    // بطاقة الطالب
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[100]!),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.person, color: Colors.blue),
                          ),
                          const SizedBox(width: 15),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _studentData!['first_name'] ?? "بدون اسم",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text("📞 ${_studentData!['phone']}"),
                              Text("👤 ${_studentData!['username']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // عنوان القسم + زر الإضافة
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("الصلاحيات الحالية:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        TextButton.icon(
                          onPressed: _showAddAccessDialog, // ✅ استدعاء النافذة الجديدة
                          icon: const Icon(Icons.playlist_add_check, size: 24),
                          label: const Text("إدارة الصلاحيات"),
                        ),
                      ],
                    ),
                    const Divider(),

                    // قائمة الصلاحيات
                    if (_accessList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text("هذا الطالب لا يملك أي صلاحيات حالياً")),
                      )
                    else
                      ..._accessList.map((item) {
                        bool isCourse = item['type'] == 'course';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          child: ListTile(
                            leading: Icon(
                              isCourse ? Icons.school : Icons.menu_book,
                              color: isCourse ? Colors.orange : Colors.purple,
                            ),
                            title: Text(item['title'] ?? "غير معرّف"),
                            subtitle: Text(item['subtitle'] ?? (isCourse ? "كورس كامل" : "مادة فردية")),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.red),
                              tooltip: "سحب الصلاحية",
                              onPressed: () => _toggleAccess(
                                item['type'], 
                                item['id'].toString(), 
                                false // false تعني سحب
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 60, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("قم بالبحث عن طالب لإدارة صلاحياته", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
