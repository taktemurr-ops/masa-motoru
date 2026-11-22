import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'chess.dart';
import 'grid_state.dart';
import 'skins.dart';

/// Dama ve satranç için damalı tahta. Açık/koyu kareler stüdyonun ahşap
/// tonları; son hamle ve hedef kareler vurgulanır.
abstract class CheckerSkin extends BoardSkin {
  const CheckerSkin();
  static const light = Color(0xFFEBD9B4);
  static const dark = Color(0xFF9C6B43);

  @override
  double aspect(BoardState s) => 1;

  Rect cell(GridState s, Size size, int i) {
    final w = size.width / s.cols;
    return Rect.fromLTWH((i % s.cols) * w, (i ~/ s.cols) * w, w, w);
  }

  void paintBoard(Canvas c, Size size, GridState s, BoardPaintInfo info, {bool allLight = false}) {
    c.drawRRect(RRect.fromRectAndRadius((Offset.zero & size).inflate(4), const Radius.circular(8)), Paint()..color = const Color(0xFF5A3A22));
    for (var i = 0; i < s.cells.length; i++) {
      final r = cell(s, size, i);
      final darkSq = !allLight && ((i % s.cols) + (i ~/ s.cols)) % 2 == 1;
      c.drawRect(r, Paint()..color = darkSq ? dark : light);
      if (allLight) {
        c.drawRect(
            r,
            Paint()
              ..color = const Color(0x55000000)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
      if (s.last == i) c.drawRect(r, Paint()..color = kHighlight.withValues(alpha: 0.32));
      if (info.selected == i) c.drawRect(r, Paint()..color = const Color(0x664CAF50));
    }
  }

  void paintMarks(Canvas c, Size size, GridState s, BoardPaintInfo info) {
    for (final t in info.targets) {
      final r = cell(s, size, t);
      drawTarget(c, r.center, r.width * (s.cells[t] >= 0 ? 0.45 : 0.16));
    }
    if (info.hintFrom != null) drawHint(c, cell(s, size, info.hintFrom!));
    if (info.hintTo != null) drawHint(c, cell(s, size, info.hintTo!));
  }

  @override
  int hit(Offset p, Size size, BoardState st) {
    final s = st as GridState;
    final w = size.width / s.cols;
    final c = (p.dx / w).floor(), r = (p.dy / w).floor();
    return s.inside(c, r) ? r * s.cols + c : -1;
  }
}

class DraughtsSkin extends CheckerSkin {
  /// Türk damasında bütün kareler aynı renk.
  final bool plain;
  const DraughtsSkin({this.plain = false});
  static const pieces = [Color(0xFFF1E9DA), Color(0xFF2A2D34)];

  void _piece(Canvas c, Offset o, double rad, int v, bool cb) {
    final p = v % 2;
    drawDisc(c, o, rad, pieces[p], ring: true);
    if (v >= 2) {
      // Dama: ortada taç.
      final crown = Path();
      final w = rad * 0.9, h = rad * 0.55;
      crown
        ..moveTo(o.dx - w / 2, o.dy + h / 2)
        ..lineTo(o.dx - w / 2, o.dy - h / 2)
        ..lineTo(o.dx - w / 4, o.dy)
        ..lineTo(o.dx, o.dy - h / 2 - h * 0.2)
        ..lineTo(o.dx + w / 4, o.dy)
        ..lineTo(o.dx + w / 2, o.dy - h / 2)
        ..lineTo(o.dx + w / 2, o.dy + h / 2)
        ..close();
      c.drawPath(crown, Paint()..color = const Color(0xFFE0A526));
    }
    if (cb) drawMark(c, o, rad, p);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    paintBoard(c, size, s, info, allLight: plain);
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v < 0) continue;
      final r = cell(s, size, i);
      _piece(c, r.center, r.width * 0.4, v, info.colorBlind);
    }
    paintMarks(c, size, s, info);
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => _piece(c, r.center, r.width * 0.45, seat, false);
}

/// Satranç taşları: stüdyonun sade vektör çizimleri (yazı tipi kullanılmaz).
class ChessSkin extends CheckerSkin {
  const ChessSkin();
  static const fill = [Color(0xFFF7F1E3), Color(0xFF2B2E36)];
  static const edge = [Color(0xFF3A3326), Color(0xFFE8E0CC)];

  static Path piecePath(int t, Rect r) {
    final w = r.width, h = r.height;
    Offset p(double x, double y) => Offset(r.left + x * w, r.top + y * h);
    final path = Path();
    void poly(List<Offset> pts) {
      path.moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      path.close();
    }

    // Ortak taban
    path.addRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.2, 0.84), p(0.8, 0.94)), Radius.circular(w * 0.04)));
    switch (t) {
      case cP:
        path.addOval(Rect.fromCircle(center: p(0.5, 0.36), radius: w * 0.15));
        poly([p(0.36, 0.84), p(0.42, 0.5), p(0.58, 0.5), p(0.64, 0.84)]);
      case cR:
        poly([p(0.3, 0.84), p(0.33, 0.38), p(0.67, 0.38), p(0.7, 0.84)]);
        poly([p(0.26, 0.38), p(0.26, 0.16), p(0.36, 0.16), p(0.36, 0.25), p(0.45, 0.25), p(0.45, 0.16), p(0.55, 0.16), p(0.55, 0.25), p(0.64, 0.25), p(0.64, 0.16), p(0.74, 0.16), p(0.74, 0.38)]);
      case cN:
        poly([p(0.28, 0.84), p(0.3, 0.6), p(0.46, 0.44), p(0.26, 0.46), p(0.24, 0.36), p(0.42, 0.18), p(0.5, 0.1), p(0.56, 0.18), p(0.7, 0.3), p(0.74, 0.84)]);
      case cB:
        poly([p(0.34, 0.84), p(0.42, 0.55), p(0.58, 0.55), p(0.66, 0.84)]);
        path.addOval(Rect.fromPoints(p(0.34, 0.2), p(0.66, 0.6)));
        path.addOval(Rect.fromCircle(center: p(0.5, 0.14), radius: w * 0.05));
      case cQ:
        poly([p(0.28, 0.84), p(0.22, 0.26), p(0.36, 0.5), p(0.42, 0.18), p(0.5, 0.46), p(0.58, 0.18), p(0.64, 0.5), p(0.78, 0.26), p(0.72, 0.84)]);
        for (final x in const [0.22, 0.42, 0.58, 0.78]) {
          path.addOval(Rect.fromCircle(center: p(x, x == 0.42 || x == 0.58 ? 0.15 : 0.23), radius: w * 0.05));
        }
      case cK:
        poly([p(0.28, 0.84), p(0.3, 0.42), p(0.7, 0.42), p(0.72, 0.84)]);
        path.addRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.36, 0.3), p(0.64, 0.44)), Radius.circular(w * 0.05)));
        path.addRect(Rect.fromPoints(p(0.46, 0.06), p(0.54, 0.3)));
        path.addRect(Rect.fromPoints(p(0.38, 0.12), p(0.62, 0.2)));
    }
    return path;
  }

  static void drawPiece(Canvas c, Rect r, int v) {
    final t = pieceType(v), col = pieceColor(v);
    final path = piecePath(t, r.deflate(r.width * 0.06));
    c.drawPath(path.shift(Offset(0, r.width * 0.03)), Paint()..color = Colors.black.withValues(alpha: 0.25));
    c.drawPath(path, Paint()..color = fill[col]);
    c.drawPath(
        path,
        Paint()
          ..color = edge[col]
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r.width * 0.035)
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    paintBoard(c, size, s, info);
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v < 0) continue;
      drawPiece(c, cell(s, size, i), v);
    }
    paintMarks(c, size, s, info);
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawPiece(c, r, seat * 8 + cK);
}
