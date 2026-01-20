import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'drawing_model.g.dart'; // تأكد من تشغيل build_runner لاحقاً

@HiveType(typeId: 1) // تأكد أن هذا ID فريد في مشروعك
class DrawingPoint extends HiveObject {
  @HiveField(0)
  final double x;
  
  @HiveField(1)
  final double y;
  
  @HiveField(2)
  final int colorValue; // نحفظ اللون كرقم
  
  @HiveField(3)
  final double width;
  
  @HiveField(4)
  final bool isHighlighter; // هل هو قلم عادي أم هايلايت؟

  DrawingPoint({
    required this.x,
    required this.y,
    required this.colorValue,
    required this.width,
    required this.isHighlighter,
  });
}

// نموذج لحفظ الخط كاملاً (مجموعة نقاط)
@HiveType(typeId: 2)
class DrawingLine extends HiveObject {
  @HiveField(0)
  final List<DrawingPoint> points;
  
  DrawingLine({required this.points});
}
