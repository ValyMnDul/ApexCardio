import 'package:flutter/material.dart';

class EcgPainter extends CustomPainter {
  final List<double> points;
  final bool showGrid;

  final Color lineColor;
  final Color gridColor;
  final Color baselineColor;

  final int maxPoints;

  EcgPainter(
    this.points,
    this.showGrid, {
    required this.lineColor,
    required this.gridColor,
    required this.baselineColor,
    this.maxPoints = 600,
  });

  static const double displayRange = 8050.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = baselineColor
        ..strokeWidth = 1.0,
    );

    if (points.length < 2) {
      return;
    }

    final start = points.length > maxPoints ? points.length - maxPoints : 0;

    final count = points.length - start;

    final dx = size.width / (maxPoints - 1);

    final centerY = size.height / 2;

    final halfHeight = size.height * 0.44;

    final path = Path();

    for (int i = 0; i < count; i++) {
      double value = points[start + i];

      value = value.clamp(-displayRange, displayRange);

      final normalized = value / displayRange;

      final x = i * dx;

      final y = centerY - normalized * halfHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final ecgPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(path, glowPaint);

    canvas.drawPath(path, ecgPaint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    const verticalDivisions = 10;

    const horizontalDivisions = 6;

    for (int i = 1; i < verticalDivisions; i++) {
      final x = size.width * i / verticalDivisions;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (int i = 1; i < horizontalDivisions; i++) {
      final y = size.height * i / horizontalDivisions;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return true;
  }
}
