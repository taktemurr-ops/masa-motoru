import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'mancala.dart';
import 'morris.dart';
import 'skins.dart';

TextPainter _num(String s, double size, Color c) => TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: c)),
      textDirection: TextDirection.ltr,
    )..layout();

// ---------------------------------------------------------------- Mangala

class MancalaSkin extends BoardSkin {
  final MancalaRules rules;
  const MancalaSkin(this.rules);

  static const wood = Color(0xFF8A5A33);
  static const pit = Color(0xFF5E3B1F);
  static const seed = [Color(0xFFE8C36A), Color(0xFF6FB6A8), Color(0xFFD9775F), Color(0xFFB9A1D9)];

  @override
  double aspect(BoardState s) => (rules.pits + 2) / 2.4;

  /// Çukurun merkezi; oyuncu 0 alt sıra (soldan sağa), oyuncu 1 üst sıra (sağdan sola).
  Rect _pit(Size size, int i) {
    final w = size.width / (rules.pits + 2);
    final h = size.height;
    if (i == rules.store(0)) return Rect.fromLTWH(size.width - w, h * 0.08, w * 0.9, h * 0.84);
    if (i == rules.store(1)) return Rect.fromLTWH(w * 0.1, h * 0.08, w * 0.9, h * 0.84);
    if (i < rules.pits) return Rect.fromLTWH(w * (i + 1), h * 0.52, w, h * 0.42).deflate(w * 0.06);
    final k = 2 * rules.pits - i;
    return Rect.fromLTWH(w * (k + 1), h * 0.06, w, h * 0.42).deflate(w * 0.06);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height * 0.2)), Paint()..color = wood);
    final rng = math.Random(7);
    for (var i = 0; i < s.cells.length; i++) {
      final r = _pit(size, i);
      final store = i == rules.store(0) || i == rules.store(1);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide * 0.45)), Paint()..color = pit);
      if (info.hintTo == i) drawHint(c, r);
      if (s.last == i) {
        c.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide * 0.45)),
            Paint()
              ..color = kHighlight.withValues(alpha: 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      final n = s.cells[i];
      final shown = math.min(n, store ? 30 : 14);
      final sr = r.shortestSide * (store ? 0.09 : 0.13);
      for (var k = 0; k < shown; k++) {
        final a = rng.nextDouble() * math.pi * 2, d = rng.nextDouble() * (r.shortestSide * 0.32);
        final o = r.center + Offset(math.cos(a) * d, math.sin(a) * d * (store ? 2.2 : 1));
        drawDisc(c, o, sr, seed[k % seed.length]);
      }
      final t = _num('$n', r.shortestSide * (store ? 0.32 : 0.28), Colors.white);
      final at = i < rules.pits || i == rules.store(0) ? Offset(r.center.dx - t.width / 2, r.bottom - t.height * 0.2) : Offset(r.center.dx - t.width / 2, r.top - t.height * 0.85);
      if (!store) t.paint(c, at);
      if (store) t.paint(c, r.center - Offset(t.width / 2, t.height / 2));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]) {
    for (var i = 0; i < (s as GridState).cells.length; i++) {
      if (_pit(size, i).inflate(4).contains(p)) return i;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    final t = _num(seat == 0 ? '▼' : '▲', r.height * 0.8, wood);
    t.paint(c, r.center - Offset(t.width / 2, t.height / 2));
  }
}

// ---------------------------------------------------------------- Dokuz taş

class MorrisSkin extends BoardSkin {
  const MorrisSkin();
  static const pieces = [Color(0xFFF1E9DA), Color(0xFF2A2D34)];

  Offset _pt(Size size, int i) {
    final (x, y) = MorrisRules.points[i];
    final step = size.width / 7;
    return Offset((x + 0.5) * step, (y + 0.5) * step);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final step = size.width / 7;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(step * 0.3)), Paint()..color = const Color(0xFFDDB777));
    final line = Paint()
      ..color = const Color(0xFF5A3A22)
      ..strokeWidth = math.max(2, step * 0.06);
    for (var i = 0; i < 24; i++) {
      for (final j in MorrisRules.adj[i]) {
        if (j > i) c.drawLine(_pt(size, i), _pt(size, j), line);
      }
    }
    for (var i = 0; i < 24; i++) {
      final o = _pt(size, i);
      c.drawCircle(o, step * 0.1, Paint()..color = const Color(0xFF5A3A22));
      final v = s.cells[i];
      if (v >= 0) {
        drawDisc(c, o, step * 0.34, pieces[v], ring: true);
        if (info.colorBlind) drawMark(c, o, step * 0.34, v);
        if (s.last == i) c.drawCircle(o, step * 0.08, Paint()..color = kHighlight);
      }
      if (info.selected == i) {
        c.drawCircle(
            o,
            step * 0.4,
            Paint()
              ..color = kHighlight
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
      if (info.targets.contains(i)) drawTarget(c, o, step * 0.14);
      if (info.hintTo == i || info.hintFrom == i) drawHint(c, Rect.fromCircle(center: o, radius: step * 0.42));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]) {
    final step = size.width / 7;
    for (var i = 0; i < 24; i++) {
      if ((_pt(size, i) - p).distance < step * 0.48) return i;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, pieces[seat]);
}

