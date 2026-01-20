import 'dart:ui';

class DrawingLine {
  final List<Offset> points;
  final int color;
  final double strokeWidth;
  final bool isHighlighter;
  final bool isEraser; // ✅ إضافة خاصية الممحاة

  DrawingLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isHighlighter,
    this.isEraser = false, // ✅ القيمة الافتراضية
  });

  Map<String, dynamic> toJson() {
    return {
      'c': color,
      'w': strokeWidth,
      'h': isHighlighter,
      'e': isEraser, // ✅ حفظ الخاصية
      'p': points.map((e) => {'x': e.dx, 'y': e.dy}).toList(),
    };
  }

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    var pts = (json['p'] as List).map((e) {
      return Offset(
        (e['x'] as num).toDouble(),
        (e['y'] as num).toDouble(),
      );
    }).toList();

    return DrawingLine(
      points: pts,
      color: json['c'] as int,
      strokeWidth: (json['w'] as num).toDouble(),
      isHighlighter: json['h'] as bool? ?? false,
      isEraser: json['e'] as bool? ?? false, // ✅ استرجاع الخاصية
    );
  }
}
