class CourseModel {
  final String id;
  final String title;
  final String teacherId;
  final String instructor; // Kept for UI convenience
  final String subject;    // Kept for UI convenience
  final String price;      // Kept for UI convenience
  final double rating;
  final int reviews;
  final String description;
  final double fullPrice;
  final String category;
  final String imagePath;

  CourseModel({
    required this.id,
    required this.title,
    required this.teacherId,
    required this.instructor,
    required this.subject,
    required this.price,
    required this.rating,
    required this.reviews,
    required this.description,
    required this.fullPrice,
    required this.category,
    required this.imagePath,
  });
}
