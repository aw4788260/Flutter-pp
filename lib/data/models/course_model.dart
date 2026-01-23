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
class CourseModel {
  final String id;
  final String title;
  final String instructor; // ✅ تم توحيد الاسم (كان instructorName)
  final String teacherId; 
  final String code;
  final double price; // ✅ تم توحيد الاسم (كان fullPrice)
  final String? description;
  final String? imageUrl; // ✅ تمت إعادة هذا الحقل الضروري للبطاقة
  final String subject;   // ✅ تمت إعادة هذا الحقل الضروري للبطاقة

  final List<dynamic> subjects; 
  final List<dynamic> exams;

  CourseModel({
    required this.id,
    required this.title,
    required this.instructor, // ✅
    this.teacherId = '',      // ✅ جعلناه اختياري بقيمة افتراضية لتجنب الأخطاء في الواجهات القديمة
    required this.code,
    required this.price,      // ✅
    this.description,
    this.imageUrl,            // ✅
    this.subject = 'General', // ✅
    this.subjects = const [],
    this.exams = const [],
  });

  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['course_id'].toString(),
      title: json['course_title'] ?? '',
      instructor: json['instructor_name'] ?? 'Instructor',
      teacherId: json['teacher_id']?.toString() ?? '', 
      code: json['code']?.toString() ?? '',
      price: (json['price'] ?? 0).toDouble(),
      description: json['description'],
      imageUrl: json['image_url'], // ✅ قراءة الصورة من الـ API
      subject: json['subject_title'] ?? 'General', // ✅ قراءة المادة أو وضع افتراضي
      subjects: [],
      exams: [],
    );
  }
}
