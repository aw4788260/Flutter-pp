import 'models/course_model.dart';
import 'models/chapter_model.dart';

// --- Models Definition (Simplified version of types.ts) ---

class User {
  final String id;
  final String name;
  final String username;
  final List<String> enrolledCourses;

  User({required this.id, required this.name, required this.username, required this.enrolledCourses});
}

class Teacher {
  final String id;
  final String name;
  final String specialty;
  final String avatar;
  final String bio;

  Teacher({required this.id, required this.name, required this.specialty, required this.avatar, required this.bio});
}

class ExamModel {
  final String id;
  final String title;
  final int durationMinutes;
  final List<Question> questions;

  ExamModel({required this.id, required this.title, required this.durationMinutes, required this.questions});
}

class Question {
  final String id;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String? imageUrl;

  Question({required this.id, required this.text, required this.options, required this.correctIndex, this.imageUrl});
}

// --- MOCK DATA ---

final ExamModel mockExam = ExamModel(
  id: 'e1',
  title: 'Material 3 Foundations Exam',
  durationMinutes: 15,
  questions: [
    Question(
      id: 'q1',
      text: 'What is the primary feature of Material You?',
      options: ['Strict color palettes', 'Dynamic color extraction', 'No shadows', '3D elements'],
      correctIndex: 1,
      imageUrl: 'https://picsum.photos/seed/m3_1/600/300',
    )
  ],
);

final List<Teacher> mockTeachers = [
  Teacher(
    id: 't1',
    name: 'Dr. Alex Rivera',
    specialty: 'UI/UX Design Master',
    avatar: 'https://i.pravatar.cc/150?u=t1',
    bio: 'Award-winning designer with 10+ years of experience in mobile interfaces.',
  ),
  Teacher(
    id: 't2',
    name: 'Eng. Sarah Jenkins',
    specialty: 'Fullstack Architect',
    avatar: 'https://i.pravatar.cc/150?u=t2',
    bio: 'Lead developer at top tech firm, passionate about React and scalable systems.',
  ),
];

// Note: CourseModel needs to be updated in the next step to match this structure completely,
// but for now we map the data to match what Home Screen expects.
final List<CourseModel> mockCourses = [
  CourseModel(
    id: 'c1',
    teacherId: 't1',
    title: 'Modern UI Design with Material 3',
    rating: 4.8,
    reviews: 1240,
    description: 'Master the latest design language by Google. Learn dynamic coloring and adaptive layouts.',
    fullPrice: 500,
    category: 'Design',
    // We will add subjects/chapters properly when updating CourseModel file
    imagePath: "assets/images/course1.png", // Placeholder
    subject: "Design", price: "500", instructor: "Dr. Alex Rivera" // Backward compatibility
  ),
  CourseModel(
    id: 'c2',
    teacherId: 't2',
    title: 'Advanced React Architecture',
    rating: 4.9,
    reviews: 2150,
    description: 'Deep dive into patterns, performance, and state management.',
    fullPrice: 800,
    category: 'Development',
    imagePath: "assets/images/course2.png", // Placeholder
    subject: "Development", price: "800", instructor: "Eng. Sarah Jenkins" // Backward compatibility
  ),
];
