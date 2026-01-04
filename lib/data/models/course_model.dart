class CourseModel {
  final String id;
  final String title;
  final String instructor;
  final String subject;
  final String price;
  final String imagePath; // يمكن أن يكون رابط انترنت أو أصل محلي

  CourseModel({
    required this.id,
    required this.title,
    required this.instructor,
    required this.subject,
    required this.price,
    required this.imagePath,
  });
}

// بيانات تجريبية (Mock Data) لتظهر في الشاشة
final List<CourseModel> dummyCourses = [
  CourseModel(
    id: "1",
    title: "Advanced Mechanics & Motion",
    instructor: "Mr. Ahmed Hassan",
    subject: "PHYSICS",
    price: "1,200 EGP",
    imagePath: "assets/images/physics_banner.png",
  ),
  CourseModel(
    id: "2",
    title: "Organic Chemistry Masterclass",
    instructor: "Dr. Sara Ali",
    subject: "CHEMISTRY",
    price: "950 EGP",
    imagePath: "assets/images/chem_banner.png",
  ),
  CourseModel(
    id: "3",
    title: "Calculus: Differentiation",
    instructor: "Eng. Mahmoud",
    subject: "MATH",
    price: "1,050 EGP",
    imagePath: "assets/images/math_banner.png",
  ),
];
