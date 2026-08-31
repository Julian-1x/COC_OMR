import 'package:flutter/material.dart';
import 'package:omr_app/models/omr_template_specs.dart';

/// Mini sheet preview: page outline, corner marks, timing marks, bubble grid.
class OmrSheetLayoutPreview extends StatelessWidget {
  const OmrSheetLayoutPreview({
    super.key,
    required this.profile,
    this.height = 220,
  });

  final OmrLayoutProfile profile;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: profile.geometry.pageWidth / profile.geometry.pageHeight,
      child: Container(
        constraints: BoxConstraints(maxHeight: height),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: CustomPaint(
            painter: _OmrSheetPreviewPainter(profile: profile),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _OmrSheetPreviewPainter extends CustomPainter {
  _OmrSheetPreviewPainter({required this.profile});

  final OmrLayoutProfile profile;

  @override
  void paint(Canvas canvas, Size size) {
    final g = profile.geometry;
    final grid = profile.grid;
    final scaleX = size.width / g.pageWidth;
    final scaleY = size.height / g.pageHeight;

    double sx(double x) => x * scaleX;
    double sy(double y) => y * scaleY;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final markPaint = Paint()..color = Colors.black;
    final corner = g.cornerMarkerSize;
    final blockLeft = 0.0;
    final blockTop = 0.0;
    final blockRight = g.contentBlockWidth;
    final blockBottom = g.contentBlockHeight;

    for (final offset in [
      Offset(blockLeft + g.cornerMarkerOffset, blockTop + g.cornerMarkerOffset),
      Offset(blockRight - g.cornerMarkerOffset - corner,
          blockTop + g.cornerMarkerOffset),
      Offset(blockLeft + g.cornerMarkerOffset,
          blockBottom - g.cornerMarkerOffset - corner),
      Offset(blockRight - g.cornerMarkerOffset - corner,
          blockBottom - g.cornerMarkerOffset - corner),
    ]) {
      canvas.drawRect(
        Rect.fromLTWH(sx(offset.dx), sy(offset.dy), sx(corner), sy(corner)),
        markPaint,
      );
    }

    final timing = g.timingMarkSize;
    final edge = g.timingMarkEdgeOffset;
    for (var x = g.timingMarkStartX; x <= g.timingMarkEndX; x += g.timingMarkSpacing) {
      canvas.drawRect(
        Rect.fromLTWH(sx(x), sy(blockTop + edge), sx(timing), sy(timing)),
        markPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
            sx(x), sy(blockBottom - edge - timing), sx(timing), sy(timing)),
        markPaint,
      );
    }
    for (var y = g.timingMarkStartY; y <= g.timingMarkEndY; y += g.timingMarkSpacing) {
      canvas.drawRect(
        Rect.fromLTWH(sx(blockLeft + edge), sy(y), sx(timing), sy(timing)),
        markPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
            sx(blockRight - edge - timing), sy(y), sx(timing), sy(timing)),
        markPaint,
      );
    }

    // OMR ID band (preview)
    final idPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawRect(
      Rect.fromLTWH(
        sx(g.marginLeft),
        sy(g.omrIdTop),
        sx(g.answerGridWidth),
        sy(g.omrIdHeight),
      ),
      idPaint,
    );

    // QR placeholder
    canvas.drawRect(
      Rect.fromLTWH(
        sx(g.qrCodeX),
        sy(g.qrCodeY),
        sx(g.qrCodeSize),
        sy(g.qrCodeSize),
      ),
      idPaint,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    canvas.drawRect(
      Rect.fromLTWH(
        sx(g.answerGridLeft),
        sy(g.answerRowsTop),
        sx(g.answerGridRight - g.answerGridLeft),
        sy(g.answerRowsBottom - g.answerRowsTop),
      ),
      gridPaint,
    );

    final bubblePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final opts = profile.optionsCount.clamp(2, 5);
    for (var row = 0; row < grid.rows; row++) {
      for (var col = 0; col < grid.columns; col++) {
        final qIndex = row * grid.columns + col;
        if (qIndex >= profile.itemCount) {
          break;
        }
        for (var opt = 0; opt < opts; opt++) {
          final cx = profile.bubbleCenterX(col, opt);
          final cy = profile.rowCenterY(row);
          final r = g.answerBubbleDiameter / 2;
          canvas.drawCircle(Offset(sx(cx), sy(cy)), (sx(r) + sy(r)) / 2, bubblePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OmrSheetPreviewPainter oldDelegate) {
    return oldDelegate.profile != profile;
  }
}
