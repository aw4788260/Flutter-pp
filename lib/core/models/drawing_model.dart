import 'dart:ui';

class DrawingLine {
  final List<Offset> points;
  final int color;
  final double strokeWidth;
  final bool isHighlighter;

  DrawingLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isHighlighter,
  });

  // تحويل البيانات إلى صيغة JSON للحفظ
  Map<String, dynamic> toJson() {
    return {
      'c': color,
      'w': strokeWidth,
      'h': isHighlighter,
      'p': points.map((e) => {'x': e.dx, 'y': e.dy}).toList(),
    };
  }

  // استرجاع البيانات من JSON
  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    // التأكد من تحويل البيانات بشكل آمن
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
    );
  }
}
