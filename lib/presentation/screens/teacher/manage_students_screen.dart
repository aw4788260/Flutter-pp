import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';

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
          content: const Text("هل أنت متأكد من حذف هذا الكورس/المادة من الطالب؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("سحب"),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isLoading = true);

    try {
      await _teacherService.toggleAccess(
        _studentData!['id'], 
        type, 
        itemId, 
        allow
      );

      // إعادة تحديث البيانات
      await _search(); // نعيد البحث لتحديث القائمة
      
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

  // دالة فتح نافذة إضافة صلاحية جديدة
  void _showAddAccessDialog() {
    String type = 'course'; // القيمة الافتراضية
    String itemId = '';
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("منح صلاحية يدوية"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: "نوع المحتوى"),
                items: const [
                  DropdownMenuItem(value: 'course', child: Text("كورس كامل")),
                  DropdownMenuItem(value: 'subject', child: Text("مادة محددة")),
                ],
                onChanged: (val) => setState(() => type = val!),
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  labelText: "ID الكورس أو المادة",
                  hintText: "انسخ الـ ID من لوحة التحكم",
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => itemId = val,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () {
                if (itemId.isNotEmpty) {
                  Navigator.pop(ctx);
                  _toggleAccess(type, itemId, true);
                }
              },
              child: const Text("إضافة"),
            ),
          ],
        ),
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
                          onPressed: _showAddAccessDialog,
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
                            subtitle: Text(isCourse ? "كورس كامل" : "مادة فردية"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.red),
                              tooltip: "سحب الصلاحية",
                              onPressed: () => _toggleAccess(
                                item['type'], 
                                item['id'], 
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
