import 'package:flutter/material.dart';

// --- Enums & Basic Types ---
enum LessonType { video, file, exam }

// --- Lesson Model ---
class Lesson {
  final String id;
  final String title;
  final LessonType type;
  final String? duration;
  final String? url;
  final String? pdfUrl;

  Lesson({
    required this.id, 
    required this.title, 
    required this.type,
    this.duration,
    this.url,
    this.pdfUrl
  });
}

// --- Chapter Model ---
class Chapter {
  final String id;
  final String title;
  final List<Lesson> lessons;

  Chapter({required this.id, required this.title, required this.lessons});
}

// --- Subject Model ---
class Subject {
  final String id;
  final String title;
  final double price;
  final List<Chapter> chapters;

  Subject({
    required this.id, 
    required this.title, 
    required this.price, 
    required this.chapters
  });
}

// --- Question & Exam Models ---
class Question {
  final String id;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String? imageUrl;

  Question({
    required this.id, 
    required this.text, 
    required this.options, 
    required this.correctIndex, 
    this.imageUrl
  });
}

class ExamModel {
  final String id;
  final String title;
  final String? subjectId;
  final int durationMinutes;
  final List<Question> questions;

  ExamModel({
    required this.id, 
    required this.title, 
    required this.durationMinutes, 
    required this.questions,
    this.subjectId,
  });
}

// --- Main Course Model ---
// استبدل المحتوى الحالي بهذا الكود المحدث
class CourseModel {
  final String id;
  final String title;
  final String instructorName; // الجديد
  final String code;           // الجديد
  final double fullPrice;
  final String? description;   // الجديد

  // هذه الحقول سنملؤها لاحقاً عند طلب التفاصيل، حالياً ستكون فارغة في شاشة البداية
  final List<dynamic> subjects; 
  final List<dynamic> exams;

  CourseModel({
    required this.id,
    required this.title,
    required this.instructorName,
    required this.code,
    required this.fullPrice,
    this.description,
    this.subjects = const [],
    this.exams = const [],
  });

  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['course_id'].toString(),
      title: json['course_title'] ?? '',
      instructorName: json['instructor_name'] ?? 'Instructor',
      code: json['code'] ?? '',
      fullPrice: (json['price'] ?? 0).toDouble(),
      description: json['description'],
      subjects: [], // لا تأتي من الـ Init API
      exams: [],
    );
  }
}
