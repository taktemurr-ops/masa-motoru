import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'connect_games.dart';

/// Ortak çizim yardımcıları.
const kHighlight = Color(0xFFFFC53D);

void drawDisc(Canvas c, Offset o, double r, Color base, {bool ring = false}) {
  c.drawCircle(o.translate(0, r * 0.08), r, Paint()..color = Colors.black.withValues(alpha: 0.28));
  c.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(base, Colors.white, 0.35)!, base, Color.lerp(base, Colors.black, 0.25)!],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: o, radius: r)));
  if (ring) {
    c.drawCircle(
        o,
        r * 0.62,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12);
  }
}

void drawTarget(Canvas c, Offset o, double r) {
  c.drawCircle(o, r, Paint()..color = kHighlight.withValues(alpha: 0.75));
}

void drawHint(Canvas c, Rect rect) {
  c.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(rect.width * 0.18)),
      Paint()
        ..color = kHighlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, rect.width * 0.08));
}

/// Renk körlüğü için taşların üstüne şekil.
void drawMark(Canvas c, Offset o, double r, int seat) {
  final p = Paint()
    ..color = Colors.white.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.16;
  if (seat == 0) {
    c.drawCircle(o, r * 0.38, p);
  } else {
    c.drawRect(Rect.fromCenter(center: o, width: r * 0.7, height: r * 0.7), p);
  }
}

// ---------------------------------------------------------------- XOX

class XoxSkin extends BoardSkin {
  const XoxSkin();

  static const _ink = [Color(0xFF2B6CB0), Color(0xFFD9534F)];

  @override
  double aspect(BoardState s) => (s as GridState).cols / s.rows;

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final cw = size.width / s.cols, ch = size.height / s.rows;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cw * 0.12)), Paint()..color = const Color(0xFFFBF7EE));
    final line = Paint()
      ..color = const Color(0xFF3A3F4B)
      ..strokeWidth = math.max(2, cw * 0.045)
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < s.cols; i++) {
      c.drawLine(Offset(i * cw, ch * 0.12), Offset(i * cw, size.height - ch * 0.12), line);
    }
    for (var i = 1; i < s.rows; i++) {
      c.drawLine(Offset(cw * 0.12, i * ch), Offset(size.width - cw * 0.12, i * ch), line);
    }
    for (var i = 0; i < s.cells.length; i++) {
      final rect = Rect.fromLTWH((i % s.cols) * cw, (i ~/ s.cols) * ch, cw, ch);
      if (s.cells[i] >= 0) _mark(c, rect.deflate(cw * 0.2), s.cells[i], last: s.last == i);
      if (info.hintTo == i) drawHint(c, rect.deflate(cw * 0.06));
    }
  }

  void _mark(Canvas c, Rect r, int seat, {bool last = false}) {
    final p = Paint()
      ..color = _ink[seat]
      ..strokeWidth = r.width * 0.16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (seat == 0) {
      c.drawLine(r.topLeft, r.bottomRight, p);
      c.drawLine(r.topRight, r.bottomLeft, p);
    } else {
      c.drawCircle(r.center, r.width / 2, p);
    }
    if (last) c.drawCircle(r.center, r.width * 0.06, Paint()..color = kHighlight);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final c = (p.dx / size.width * s.cols).floor(), r = (p.dy / size.height * s.rows).floor();
    return s.inside(c, r) ? r * s.cols + c : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => _mark(c, r.deflate(3), seat);
}

// ---------------------------------------------------------------- Taşlı ızgara

/// Kare ızgarada yuvarlak taşlar: Dörtle (delikli dikey tahta), Reversi
/// (yeşil keçe), Beşleme (ahşap, kesişim noktaları).
enum DiscBoard { frame, felt, wood }

class DiscSkin extends BoardSkin {
  final DiscBoard board;
  final List<Color> pieces;
  const DiscSkin(this.board, this.pieces);

  @override
  double aspect(BoardState s) => (s as GridState).cols / s.rows;

  Rect _cell(GridState s, Size size, int i) {
    final cw = size.width / s.cols, ch = size.height / s.rows;
    return Rect.fromLTWH((i % s.cols) * cw, (i ~/ s.cols) * ch, cw, ch);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final cw = size.width / s.cols;
    final whole = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cw * 0.18));
    switch (board) {
      case DiscBoard.frame:
        c.drawRRect(whole, Paint()..color = const Color(0xFF24508F));
      case DiscBoard.felt:
        c.drawRRect(whole, Paint()..color = const Color(0xFF1E6B4E));
        final g = Paint()
          ..color = const Color(0xFF14513A)
          ..strokeWidth = 1.2;
        for (var i = 1; i < s.cols; i++) {
          c.drawLine(Offset(i * cw, 0), Offset(i * cw, size.height), g);
        }
        for (var i = 1; i < s.rows; i++) {
          c.drawLine(Offset(0, i * size.height / s.rows), Offset(size.width, i * size.height / s.rows), g);
        }
      case DiscBoard.wood:
        c.drawRRect(whole, Paint()..color = const Color(0xFFDDB777));
        final g = Paint()
          ..color = const Color(0xFF6B4A22)
          ..strokeWidth = 1;
        final ch = size.height / s.rows;
        for (var i = 0; i < s.cols; i++) {
          c.drawLine(Offset((i + 0.5) * cw, ch / 2), Offset((i + 0.5) * cw, size.height - ch / 2), g);
        }
        for (var i = 0; i < s.rows; i++) {
          c.drawLine(Offset(cw / 2, (i + 0.5) * ch), Offset(size.width - cw / 2, (i + 0.5) * ch), g);
        }
    }
    final targets = <int>{for (final t in info.targets) t};
    for (var i = 0; i < s.cells.length; i++) {
      final rect = _cell(s, size, i);
      final v = s.cells[i];
      final rad = rect.width * (board == DiscBoard.wood ? 0.44 : 0.4);
      if (board == DiscBoard.frame && v < 0) {
        c.drawCircle(rect.center, rad, Paint()..color = const Color(0xFF0F2547));
      }
      if (v >= 0 && v < pieces.length) {
        drawDisc(c, rect.center, rad, pieces[v], ring: board == DiscBoard.frame);
        if (info.colorBlind) drawMark(c, rect.center, rad, v);
        if (s.last == i) c.drawCircle(rect.center, rad * 0.22, Paint()..color = kHighlight);
      }
      if (targets.contains(i)) drawTarget(c, rect.center, rad * 0.3);
      if (info.hintTo == i) drawHint(c, rect);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final c = (p.dx / size.width * s.cols).floor(), r = (p.dy / size.height * s.rows).floor();
    if (!s.inside(c, r)) return -1;
    if (board == DiscBoard.frame) {
      // Dörtle: sütuna dokunmak yeter; en alttaki boş yuva seçilir.
      for (var rr = s.rows - 1; rr >= 0; rr--) {
        if (s.cells[rr * s.cols + c] < 0) return rr * s.cols + c;
      }
      return -1;
    }
    return r * s.cols + c;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.45, pieces[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.45, seat);
  }
}

// ---------------------------------------------------------------- Hex

class HexSkin extends BoardSkin {
  const HexSkin();
  static const _p = [Color(0xFFC0392B), Color(0xFF2E6DB4)];

  @override
  double aspect(BoardState s) {
    final n = (s as GridState).cols;
    return (n + (n - 1) / 2) / ((n - 1) * 0.866 + 1.15);
  }

  (double, Offset) _geo(int n, Size size) {
    final w = size.width / (n + (n - 1) / 2);
    return (w, Offset(w / 2, w * 0.58));
  }

  Offset _center(int n, Size size, int i) {
    final (w, o) = _geo(n, size);
    final c = i % n, r = i ~/ n;
    return o + Offset(c * w + r * w / 2, r * w * 0.866);
  }

  Path _hexPath(Offset o, double rad) {
    final p = Path();
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 6 + k * math.pi / 3;
      final pt = o + Offset(math.cos(a) * rad, math.sin(a) * rad);
      k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final n = s.cols;
    final (w, _) = _geo(n, size);
    final rad = w / math.sqrt(3) * 1.0;
    // Kenar renkleri: üst/alt oyuncu 0, sol/sağ oyuncu 1.
    final edge = Paint()..strokeWidth = w * 0.18;
    for (var k = 0; k < n; k++) {
      edge.color = _p[0];
      c.drawCircle(_center(n, size, k) - Offset(0, rad * 0.95), w * 0.08, edge);
      c.drawCircle(_center(n, size, (n - 1) * n + k) + Offset(0, rad * 0.95), w * 0.08, edge);
      edge.color = _p[1];
      c.drawCircle(_center(n, size, k * n) - Offset(rad * 0.95, 0), w * 0.08, edge);
      c.drawCircle(_center(n, size, k * n + n - 1) + Offset(rad * 0.95, 0), w * 0.08, edge);
    }
    for (var i = 0; i < s.cells.length; i++) {
      final o = _center(n, size, i);
      final v = s.cells[i];
      c.drawPath(_hexPath(o, rad * 0.97), Paint()..color = const Color(0xFFEFE6D2));
      c.drawPath(
          _hexPath(o, rad * 0.97),
          Paint()
            ..color = const Color(0xFF8A7B60)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (v >= 0) {
        drawDisc(c, o, rad * 0.72, _p[v]);
        if (info.colorBlind) drawMark(c, o, rad * 0.72, v);
        if (s.last == i) c.drawCircle(o, rad * 0.18, Paint()..color = kHighlight);
      }
      if (info.hintTo == i) c.drawPath(_hexPath(o, rad * 0.8), Paint()..color = kHighlight.withValues(alpha: 0.6));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    var best = -1;
    var bd = double.infinity;
    for (var i = 0; i < s.cells.length; i++) {
      final d = (_center(s.cols, size, i) - p).distanceSquared;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, _p[seat]);
}

// ---------------------------------------------------------------- Noktalar ve kutular

class DotsSkin extends BoardSkin {
  final DotsRules rules;
  const DotsSkin(this.rules);
  static const _p = [Color(0xFF2E6DB4), Color(0xFFD35400)];

  @override
  double aspect(BoardState s) => (rules.w + 0.6) / (rules.h + 0.6);

  double _step(Size size) => size.width / (rules.w + 0.6);
  Offset _dot(Size size, int c, int r) {
    final st = _step(size);
    return Offset(st * (0.3 + c), st * (0.3 + r));
  }

  (Offset, Offset) _edge(Size size, int e) {
    if (e < rules.hCount) {
      final c = e % rules.w, r = e ~/ rules.w;
      return (_dot(size, c, r), _dot(size, c + 1, r));
    }
    final x = e - rules.hCount;
    final c = x % (rules.w + 1), r = x ~/ (rules.w + 1);
    return (_dot(size, c, r), _dot(size, c, r + 1));
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final step = _step(size);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(step * 0.2)), Paint()..color = const Color(0xFFFBF7EE));
    for (var b = 0; b < rules.w * rules.h; b++) {
      final o = s.cells[rules.edges + b];
      if (o < 0) continue;
      final tl = _dot(size, b % rules.w, b ~/ rules.w);
      c.drawRect(Rect.fromLTWH(tl.dx, tl.dy, step, step).deflate(step * 0.06), Paint()..color = _p[o].withValues(alpha: 0.28));
      if (info.colorBlind) drawMark(c, tl + Offset(step / 2, step / 2), step * 0.3, o);
    }
    for (var e = 0; e < rules.edges; e++) {
      final (a, b) = _edge(size, e);
      final v = s.cells[e];
      if (v >= 0) {
        c.drawLine(
            a,
            b,
            Paint()
              ..color = s.last == e ? Color.lerp(_p[v], kHighlight, 0.5)! : _p[v]
              ..strokeWidth = step * 0.1
              ..strokeCap = StrokeCap.round);
      } else if (info.hintTo == e) {
        c.drawLine(
            a,
            b,
            Paint()
              ..color = kHighlight
              ..strokeWidth = step * 0.1
              ..strokeCap = StrokeCap.round);
      } else {
        c.drawLine(
            a,
            b,
            Paint()
              ..color = const Color(0x22000000)
              ..strokeWidth = step * 0.05);
      }
    }
    for (var r = 0; r <= rules.h; r++) {
      for (var col = 0; col <= rules.w; col++) {
        c.drawCircle(_dot(size, col, r), step * 0.08, Paint()..color = const Color(0xFF2B2F3A));
      }
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    var best = -1;
    var bd = double.infinity;
    final step = _step(size);
    for (var e = 0; e < rules.edges; e++) {
      final (a, b) = _edge(size, e);
      final d = (p - (a + b) / 2).distance;
      if (d < bd) {
        bd = d;
        best = e;
      }
    }
    return bd < step * 0.6 ? best : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(3), const Radius.circular(3)), Paint()..color = _p[seat]);
}

/// Taş renk takımları.
const kRedYellow = [Color(0xFFE74C3C), Color(0xFFF4C430)];
const kBlackWhite = [Color(0xFF2A2D34), Color(0xFFF2EEE4)];
