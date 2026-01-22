import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/constants/app_colors.dart'; 

class ManageTeamScreen extends StatefulWidget {
  const ManageTeamScreen({Key? key}) : super(key: key);

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {
  final TeacherService _teacherService = TeacherService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _teamMembers = []; // المشرفون الحاليون
  List<dynamic> _searchResults = []; // نتائج البحث
  bool _isLoadingTeam = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  // جلب المشرفين الحاليين
  Future<void> _loadTeam() async {
    setState(() => _isLoadingTeam = true);
    try {
      final data = await _teacherService.getTeamMembers();
      if (mounted) {
        setState(() {
          _teamMembers = data;
          _isLoadingTeam = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTeam = false);
        // يمكن إضافة تنبيه هنا في حال الفشل
      }
    }
  }

  // البحث عن طلاب لترقيتهم
  Future<void> _searchStudents(String query) async {
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _teacherService.searchStudentsForTeam(query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // تنفيذ الترقية أو الحذف
  Future<void> _handleAction(String userId, String action, String confirmText) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'promote' ? "ترقية الطالب" : "حذف المشرف"),
        content: Text(confirmText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'promote' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("تأكيد"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // إظهار مؤشر تحميل
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator())
    );

    try {
      await _teacherService.manageTeamMember(action: action, userId: userId);
      
      if (mounted) {
        Navigator.pop(context); // إغلاق اللودينج
        
        // تنظيف وإعادة تحميل البيانات
        if (action == 'promote') {
           _searchController.clear();
           setState(() => _searchResults = []);
        }
        await _loadTeam(); // تحديث قائمة الفريق

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'promote' ? "تمت الترقية ومنح الصلاحيات بنجاح" : "تم حذف المشرف بنجاح"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق اللودينج
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("إدارة فريق العمل"),
        elevation: 0,
      ),
      body: Column(
        children: [
          // -----------------------------------------------------
          // 1. قسم البحث والترقية
          // -----------------------------------------------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withOpacity(0.1), // لون خلفية خفيف
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "إضافة مشرف جديد", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)
                ),
                const SizedBox(height: 5),
                const Text(
                  "ابحث عن طالب لترقيته ومنحه صلاحيات كاملة تلقائياً", 
                  style: TextStyle(fontSize: 12, color: Colors.grey)
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "ابحث بالاسم أو اسم المستخدم...",
                    prefixIcon: const Icon(Icons.person_search, color: Colors.grey),
                    suffixIcon: _isSearching 
                        ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) 
                        : (_searchController.text.isNotEmpty 
                            ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              }) 
                            : null),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => _searchStudents(val),
                ),
              ],
            ),
          ),

          // -----------------------------------------------------
          // 2. قائمة نتائج البحث (تظهر فقط عند البحث)
          // -----------------------------------------------------
          if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 5),
                    child: Text("نتائج البحث:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final student = _searchResults[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(Icons.person_outline, color: Colors.blue),
                          ),
                          title: Text(student['first_name'] ?? "No Name", style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("@${student['username']} • ${student['phone']}"),
                          trailing: ElevatedButton(
                            onPressed: () => _handleAction(
                              student['id'].toString(), 
                              'promote', 
                              "سيتم ترقية الطالب '${student['first_name']}' ليصبح مشرفاً وسيتم منحه صلاحية الوصول لجميع كورساتك الحالية.\n\nهل أنت متأكد؟"
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green, 
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(60, 32)
                            ),
                            child: const Text("ترقية"),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(thickness: 5, color: Color(0xFFF0F0F0)), // فاصل سميك
                ],
              ),
            ),

          // -----------------------------------------------------
          // 3. قائمة المشرفين الحاليين
          // -----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.textPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  "المشرفون الحاليون (${_teamMembers.length})", 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoadingTeam
                ? const Center(child: CircularProgressIndicator())
                : _teamMembers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_off_outlined, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 10),
                            const Text("لا يوجد مشرفين حالياً", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _teamMembers.length,
                        itemBuilder: (context, index) {
                          final member = _teamMembers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: const CircleAvatar(
                                radius: 25,
                                backgroundColor: AppColors.textPrimary,
                                child: Icon(Icons.security, color: AppColors.accentYellow),
                              ),
                              title: Text(
                                member['first_name'] ?? "Unknown",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  "@${member['username']} • ${member['phone']}",
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                tooltip: "إلغاء الإشراف",
                                onPressed: () => _handleAction(
                                  member['id'].toString(), 
                                  'demote', 
                                  "سيتم سحب صلاحيات الإشراف من '${member['first_name']}' وإعادته كطالب عادي.\n\nلن يتمكن من إدارة المحتوى بعد الآن."
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
