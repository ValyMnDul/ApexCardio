import 'package:flutter/material.dart';

class EcgPainter extends CustomPainter {
  final List<double> points;

  EcgPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    double gridSpacing = 20.0;
    for (double x = 0; x < size.width; x = x + gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y = y + gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final ecgPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (points.isEmpty) return;

    final path = Path();

    double dx = size.width / 300;
    double centerY = size.height / 2;

    for (int i = 0; i < points.length; i++) {
      double x = i * dx;
      double y = centerY - (points[i] * 1000);

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
