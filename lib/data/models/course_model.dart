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
  final String teacherId;
  final double rating;
  final int reviews;
  final String description;
  final double fullPrice;
  final String category;
  final List<Subject> subjects;
  final List<ExamModel> exams;
  
  // خاصية إضافية للتوافق مع واجهات سابقة إذا لزم الأمر
  String get instructorName => "Instructor"; 

  CourseModel({
    required this.id,
    required this.title,
    required this.teacherId,
    required this.rating,
    required this.reviews,
    required this.description,
    required this.fullPrice,
    required this.category,
    this.subjects = const [],
    this.exams = const [],
  });
}
