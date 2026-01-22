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

  // دالة سحب أو منح الصلاحية
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

  // ✅ النافذة الذكية لمنح الصلاحيات (مع استثناء المملوك مسبقاً)
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

    String? selectedCourseId;
    String? selectedSubjectId;
    bool isFullCourse = true; // الحالة الافتراضية: كورس كامل

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          // --- فلترة الكورسات المتاحة للإضافة ككورس كامل ---
          final availableCoursesForFull = _myContent
              .where((c) => !ownedCourseIds.contains(c['id'].toString()))
              .toList();
          
          // --- فلترة الكورسات لاستخدامها عند اختيار "مادة" ---
          // نعرض كل الكورسات للبحث بداخلها عن مواد، أو يمكن فلترتها أيضاً إذا كان الكورس مملوكاً بالكامل (اختياري)
          final allMyCourses = _myContent; 

          // --- العثور على الكورس المختار حالياً لجلب مواده ---
          final selectedCourseData = _myContent.firstWhere(
              (c) => c['id'].toString() == selectedCourseId, 
              orElse: () => null
          );
          
          // --- فلترة المواد داخل الكورس المختار (استبعاد المواد المملوكة) ---
          final List availableSubjects = selectedCourseData != null 
              ? (selectedCourseData['subjects'] as List)
                  .where((s) => !ownedSubjectIds.contains(s['id'].toString()))
                  .toList()
              : [];

          return AlertDialog(
            title: const Text("منح صلاحية جديدة"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. اختيار النوع (كورس كامل / مادة)
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text("كورس كامل", style: TextStyle(fontSize: 13)),
                        value: true,
                        groupValue: isFullCourse,
                        onChanged: (val) => setDialogState(() { 
                          isFullCourse = val!; 
                          selectedCourseId = null; // إعادة تعيين الاختيار
                          selectedSubjectId = null;
                        }),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text("مادة محددة", style: TextStyle(fontSize: 13)),
                        value: false,
                        groupValue: isFullCourse,
                        onChanged: (val) => setDialogState(() { 
                          isFullCourse = val!;
                          selectedCourseId = null;
                          selectedSubjectId = null;
                        }),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const Divider(),

                // 2. القوائم المنسدلة بناءً على النوع
                if (isFullCourse) ...[
                  // --- وضع الكورس الكامل ---
                  if (availableCoursesForFull.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text("الطالب يمتلك جميع كورساتك بالفعل.", style: TextStyle(color: Colors.grey)),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedCourseId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "اختر الكورس", 
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15)
                      ),
                      items: availableCoursesForFull.map<DropdownMenuItem<String>>((course) {
                        return DropdownMenuItem(value: course['id'].toString(), child: Text(course['title']));
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedCourseId = val),
                    ),
                ] else ...[
                  // --- وضع المادة المحددة ---
                  // قائمة الكورسات أولاً
                  DropdownButtonFormField<String>(
                    value: selectedCourseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "اختر الكورس (لعرض مواده)", 
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15)
                    ),
                    items: allMyCourses.map<DropdownMenuItem<String>>((course) {
                      return DropdownMenuItem(value: course['id'].toString(), child: Text(course['title']));
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedCourseId = val;
                        selectedSubjectId = null; // تصفير المادة عند تغيير الكورس
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  
                  // قائمة المواد (تظهر فقط بعد اختيار الكورس)
                  if (selectedCourseId != null)
                    if (availableSubjects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text("الطالب يمتلك جميع مواد هذا الكورس.", style: TextStyle(color: Colors.grey)),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: selectedSubjectId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "اختر المادة", 
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15)
                        ),
                        items: availableSubjects.map<DropdownMenuItem<String>>((subject) {
                          return DropdownMenuItem(value: subject['id'].toString(), child: Text(subject['title']));
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedSubjectId = val),
                      ),
                ]
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () {
                  if (isFullCourse) {
                    if (selectedCourseId != null) {
                      Navigator.pop(ctx);
                      _toggleAccess('course', selectedCourseId!, true);
                    }
                  } else {
                    if (selectedSubjectId != null) {
                      Navigator.pop(ctx);
                      _toggleAccess('subject', selectedSubjectId!, true);
                    }
                  }
                },
                child: const Text("منح"),
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
                          icon: const Icon(Icons.add_circle, size: 20),
                          label: const Text("منح صلاحية"),
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
                            // ✅ عرض تفاصيل إضافية (مثل اسم الكورس للمادة) إذا كانت متوفرة
                            subtitle: Text(item['subtitle'] ?? (isCourse ? "كورس كامل" : "مادة فردية")),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.red),
                              tooltip: "سحب الصلاحية",
                              // ✅ استدعاء دالة السحب بالبيانات الصحيحة
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
