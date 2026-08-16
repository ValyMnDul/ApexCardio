import 'package:flutter/material.dart';

class EcgPainter extends CustomPainter {
  final List<double> points;
  final bool showGrid;

  EcgPainter(this.points, this.showGrid);

  static const double displayRange = 8050.0;

  static const int maxPoints = 300;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.15)
        ..strokeWidth = 1.0;

      const double gridSpacing = 20.0;

      for (double x = 0; x < size.width; x += gridSpacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }

      for (double y = 0; y < size.height; y += gridSpacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    if (points.length < 2) {
      return;
    }

    final ecgPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path();

    double centerY = size.height / 2;

    double halfHeight = size.height / 2;

    double dx = size.width / (maxPoints - 1);

    for (int i = 0; i < points.length; i++) {
      double value = points[i].clamp(-displayRange, displayRange).toDouble();

      double normalized = value / displayRange;

      double x = i * dx;

      double y = centerY - normalized * halfHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, ecgPaint);
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return true;
  }
}
