import 'package:flutter/material.dart';

class RespirationPainter extends CustomPainter {
  final List<double> points;
  final double displayRange;
  final bool showGrid;

  final Color lineColor;
  final Color gridColor;
  final Color baselineColor;

  final int maxPoints;

  RespirationPainter(
    this.points,
    this.displayRange,
    this.showGrid, {
    required this.lineColor,
    required this.gridColor,
    required this.baselineColor,
    this.maxPoints = 600,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    final centerY = size.height / 2;

    final baselinePaint = Paint()
      ..color = baselineColor
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      baselinePaint,
    );

    if (points.length < 2) {
      return;
    }

    double range = displayRange;

    if (range < 1.0) {
      range = 1.0;
    }

    final start = points.length > maxPoints ? points.length - maxPoints : 0;

    final count = points.length - start;

    final dx = size.width / (maxPoints - 1);

    final halfHeight = size.height * 0.38;

    final path = Path();

    for (int i = 0; i < count; i++) {
      double value = points[start + i];

      value = value.clamp(-range, range).toDouble();

      final normalized = value / range;

      final x = i * dx;

      final y = centerY - normalized * halfHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.08)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final respirationPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(path, glowPaint);

    canvas.drawPath(path, respirationPaint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.22)
      ..strokeWidth = 1.0;

    const verticalDivisions = 10;
    const horizontalDivisions = 4;

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
  bool shouldRepaint(covariant RespirationPainter oldDelegate) {
    return true;
  }
}
