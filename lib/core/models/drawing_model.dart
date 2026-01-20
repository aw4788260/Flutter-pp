import 'dart:ui'; // ضروري للتعرف على Offset

class DrawingLine {
  // النقاط المكونة للخط
  final List<Offset> points;
  // لون الخط (قيمة int)
  final int color;
  // سمك الخط
  final double strokeWidth;
  // هل هو قلم تظليل؟
  final bool isHighlighter;

  DrawingLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isHighlighter,
  });

  // تحويل الكائن إلى JSON للحفظ في Hive
  Map<String, dynamic> toJson() {
    return {
      'c': color,
      'w': strokeWidth,
      'h': isHighlighter,
      // نحفظ النقاط كقائمة من الخرائط الصغيرة لتقليل الحجم
      'p': points.map((e) => {'x': e.dx, 'y': e.dy}).toList(),
    };
  }

  // إنشاء الكائن من JSON عند الاسترجاع
  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    var rawPoints = json['p'] as List;
    var pts = rawPoints.map((e) {
      // التأكد من تحويل القيم إلى double لتجنب أخطاء النوع
      double x = (e['x'] as num).toDouble();
      double y = (e['y'] as num).toDouble();
      return Offset(x, y);
    }).toList();

    return DrawingLine(
      points: pts,
      color: json['c'] as int,
      strokeWidth: (json['w'] as num).toDouble(),
      isHighlighter: json['h'] as bool? ?? false,
    );
  }
}
