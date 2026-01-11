void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // -----------------------------------------------------------
    // 🔥 هذا الكود سيكشف لك سبب الشاشة البيضاء فوراً 🔥
    // -----------------------------------------------------------
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.blueGrey.shade900, // لون خلفية داكن
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
                const SizedBox(height: 10),
                const Text(
                  "UI BUILD ERROR",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 20),
                Text(
                  details.exception.toString(), // 👈 هنا سيظهر سبب المشكلة
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    };
    // -----------------------------------------------------------

    runApp(const EduVantageApp());
    
  }, (error, stack) {
    // ... كود تسجيل الأخطاء القديم
    print(error);
  });
}
