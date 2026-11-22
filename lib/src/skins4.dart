import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'abstract2.dart';
import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'skins.dart';

const _woodDark = Color(0xFF6B4A22);
const _pegs = [Color(0xFFC0392B), Color(0xFF2E6FB0)];

void _selectRing(Canvas c, Offset o, double r) => c.drawCircle(
    o,
    r,
    Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, r * 0.18));

void _lastDot(Canvas c, Offset o, double r) => c.drawCircle(o, r * 0.22, Paint()..color = kHighlight);

// ---------------------------------------------------------------- Halma

/// Kare Halma: açık ahşap tahta, köşe kampları renkli.
class HalmaSkin extends BoardSkin {
  const HalmaSkin();

  @override
  double aspect(BoardState s) => 1;

  Rect _cell(GridState s, Size size, int i) {
    final w = size.width / s.cols;
    return Rect.fromLTWH((i % s.cols) * w, (i ~/ s.cols) * w, w, w);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final rules = JumpRaceRules.halma(s.cols);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)), Paint()..color = _woodDark);
    for (var i = 0; i < s.cells.length; i++) {
      final r = _cell(s, size, i).deflate(1);
      final cc = i % s.cols, rr = i ~/ s.cols;
      var col = (cc + rr).isEven ? const Color(0xFFF1DDB8) : const Color(0xFFE2C796);
      if (rules.inCamp(cc, rr, 0)) col = Color.lerp(col, _pegs[0], 0.18)!;
      if (rules.inCamp(cc, rr, 1)) col = Color.lerp(col, _pegs[1], 0.18)!;
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.12)), Paint()..color = col);
      c.drawCircle(r.center, r.width * 0.1, Paint()..color = const Color(0x33000000));
      final v = s.cells[i];
      if (v >= 0) {
        drawDisc(c, r.center, r.width * 0.36, _pegs[v]);
        if (info.colorBlind) drawMark(c, r.center, r.width * 0.36, v);
        if (s.last == i) _lastDot(c, r.center, r.width * 0.36);
      }
      if (info.selected == i) _selectRing(c, r.center, r.width * 0.44);
      if (info.targets.contains(i)) drawTarget(c, r.center, r.width * 0.16);
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, r);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final w = size.width / s.cols;
    final c = (p.dx / w).floor(), r = (p.dy / w).floor();
    return s.inside(c, r) ? r * s.cols + c : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, _pegs[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}

// ---------------------------------------------------------------- Çin daması

/// Altı köşeli yıldız tahta (eksenel koordinat, 17×17 ızgara).
class StarSkin extends BoardSkin {
  const StarSkin();

  @override
  double aspect(BoardState s) => 13 / 14.9;

  ({double u, double ox, double oy}) _geo(Size size) {
    // x = q + r/2 -8 .. ; y = r*√3/2. Genişlik 13 birim, yükseklik 16·√3/2.
    final u = math.min(size.width / 13, size.height / 14.9);
    return (u: u, ox: size.width / 2, oy: size.height / 2);
  }

  Offset _pos(int i, Size size) {
    final g = _geo(size);
    final q = i % 17 - 8, r = i ~/ 17 - 8;
    return Offset(g.ox + (q + r / 2) * g.u, g.oy + r * math.sqrt(3) / 2 * g.u);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final g = _geo(size);
    // Yıldız zemini.
    final star = Path();
    // Uçlar -90°'den başlayarak her 60°'de bir.
    final rad = 7.6 * g.u;
    for (var k = 0; k < 12; k++) {
      final a = -math.pi / 2 + k * math.pi / 6;
      final rr = k.isEven ? rad : 4.6 * g.u;
      final p = Offset(g.ox + rr * math.cos(a), g.oy + rr * math.sin(a));
      if (k == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    c.drawPath(star, Paint()..color = const Color(0xFF3C5A78));
    const rules = JumpRaceRules.star();
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v == -2) continue;
      final o = _pos(i, size);
      final q = i % 17, r = i ~/ 17;
      var hole = const Color(0xFF253B52);
      if (rules.inCamp(q, r, 0)) hole = Color.lerp(hole, _pegs[0], 0.35)!;
      if (rules.inCamp(q, r, 1)) hole = Color.lerp(hole, _pegs[1], 0.45)!;
      c.drawCircle(o, g.u * 0.34, Paint()..color = hole);
      if (v >= 0) {
        drawDisc(c, o, g.u * 0.4, _pegs[v]);
        if (info.colorBlind) drawMark(c, o, g.u * 0.4, v);
        if (s.last == i) _lastDot(c, o, g.u * 0.4);
      }
      if (info.selected == i) _selectRing(c, o, g.u * 0.48);
      if (info.targets.contains(i)) drawTarget(c, o, g.u * 0.16);
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: g.u * 0.5));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final g = _geo(size);
    var best = -1;
    var bd = g.u * 0.55;
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] == -2) continue;
      final d = (_pos(i, size) - p).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, _pegs[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}

// ---------------------------------------------------------------- Alquerque / Fanorona

/// Çizgili nokta tahtası: dik çizgiler ve (satır+sütun çift) noktalardan
/// geçen çaprazlar.
class LinesSkin extends BoardSkin {
  const LinesSkin();
  static const pieces = [Color(0xFFF2EEE4), Color(0xFF2A2D34)];

  @override
  double aspect(BoardState s) => (s as GridState).cols / s.rows;

  Offset pos(GridState s, Size size, int i) {
    final cw = size.width / s.cols, ch = size.height / s.rows;
    return Offset((i % s.cols + 0.5) * cw, (i ~/ s.cols + 0.5) * ch);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFFC79A5B));
    final line = Paint()
      ..color = _woodDark
      ..strokeWidth = 2;
    for (var r = 0; r < s.rows; r++) {
      c.drawLine(pos(s, size, r * s.cols), pos(s, size, r * s.cols + s.cols - 1), line);
    }
    for (var col = 0; col < s.cols; col++) {
      c.drawLine(pos(s, size, col), pos(s, size, (s.rows - 1) * s.cols + col), line);
    }
    for (var r = 0; r < s.rows - 1; r++) {
      for (var col = 0; col < s.cols - 1; col++) {
        if ((r + col).isEven) {
          c.drawLine(pos(s, size, r * s.cols + col), pos(s, size, (r + 1) * s.cols + col + 1), line);
        } else {
          c.drawLine(pos(s, size, r * s.cols + col + 1), pos(s, size, (r + 1) * s.cols + col), line);
        }
      }
    }
    final rad = math.min(size.width / s.cols, size.height / s.rows) * 0.36;
    for (var i = 0; i < s.cells.length; i++) {
      final o = pos(s, size, i);
      final v = s.cells[i];
      if (v >= 0) {
        drawDisc(c, o, rad, pieces[v], ring: true);
        if (info.colorBlind) drawMark(c, o, rad, v);
        if (s.last == i) _lastDot(c, o, rad);
      } else {
        c.drawCircle(o, rad * 0.18, Paint()..color = _woodDark);
      }
      if (info.selected == i) _selectRing(c, o, rad * 1.15);
      if (info.targets.contains(i)) drawTarget(c, o, rad * (v >= 0 ? 0.5 : 0.35));
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: rad * 1.2));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final c = (p.dx / size.width * s.cols).floor(), r = (p.dy / size.height * s.rows).floor();
    return s.inside(c, r) ? r * s.cols + c : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, pieces[seat], ring: true);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}

// ---------------------------------------------------------------- Surakarta

class SurakartaSkin extends BoardSkin {
  const SurakartaSkin();
  static const pieces = [Color(0xFFD9534F), Color(0xFF2F6E9E)];

  @override
  double aspect(BoardState s) => 1;

  double _step(Size size) => size.width / 9;
  Offset _pos(Size size, int i) {
    final st = _step(size);
    return Offset((i % 6 + 1.5) * st, (i ~/ 6 + 1.5) * st);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final step = _step(size);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFFEFE3C8));
    final colors = [const Color(0xFF3E8E6B), const Color(0xFFB0753B)];
    for (var k = 1; k <= 2; k++) {
      final p = Paint()
        ..color = colors[k - 1]
        ..style = PaintingStyle.stroke
        ..strokeWidth = step * 0.09;
      final a = k, b = 5 - k;
      c.drawLine(_pos(size, a * 6), _pos(size, a * 6 + 5), p);
      c.drawLine(_pos(size, b * 6), _pos(size, b * 6 + 5), p);
      c.drawLine(_pos(size, a), _pos(size, 30 + a), p);
      c.drawLine(_pos(size, b), _pos(size, 30 + b), p);
      // Köşe halkaları: çeyrekten büyük yaylar.
      final rad = step * k;
      for (final (cx, cy, start) in [(0.0, 0.0, math.pi / 2), (5.0, 0.0, math.pi), (5.0, 5.0, -math.pi / 2), (0.0, 5.0, 0.0)]) {
        final center = Offset((cx + 1.5) * step, (cy + 1.5) * step);
        c.drawArc(Rect.fromCircle(center: center, radius: rad), start, math.pi * 1.5, false, p);
      }
    }
    final grid = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 1;
    for (var k = 0; k < 6; k++) {
      c.drawLine(_pos(size, k * 6), _pos(size, k * 6 + 5), grid);
      c.drawLine(_pos(size, k), _pos(size, 30 + k), grid);
    }
    for (var i = 0; i < 36; i++) {
      final o = _pos(size, i);
      final v = s.cells[i];
      if (v >= 0) {
        drawDisc(c, o, step * 0.36, pieces[v]);
        if (info.colorBlind) drawMark(c, o, step * 0.36, v);
        if (s.last == i) _lastDot(c, o, step * 0.36);
      }
      if (info.selected == i) _selectRing(c, o, step * 0.44);
      if (info.targets.contains(i)) drawTarget(c, o, step * (v >= 0 ? 0.2 : 0.14));
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: step * 0.48));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final step = _step(size);
    final c = (p.dx / step - 1).floor(), r = (p.dy / step - 1).floor();
    return c >= 0 && r >= 0 && c < 6 && r < 6 ? r * 6 + c : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, pieces[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}

// ---------------------------------------------------------------- Tafl

class TaflSkin extends BoardSkin {
  const TaflSkin();
  static const pieces = [Color(0xFF2A2D34), Color(0xFFF2EEE4)];

  @override
  double aspect(BoardState s) => 1;

  Rect _cell(GridState s, Size size, int i) {
    final w = size.width / s.cols;
    return Rect.fromLTWH((i % s.cols) * w, (i ~/ s.cols) * w, w, w);
  }

  void _piece(Canvas c, Offset o, double r, int v, bool cb) {
    if (v == 2) {
      drawDisc(c, o, r * 1.08, const Color(0xFFE9C46A));
      final p = Path()
        ..moveTo(o.dx - r * 0.5, o.dy + r * 0.3)
        ..lineTo(o.dx - r * 0.5, o.dy - r * 0.25)
        ..lineTo(o.dx - r * 0.25, o.dy + r * 0.02)
        ..lineTo(o.dx, o.dy - r * 0.42)
        ..lineTo(o.dx + r * 0.25, o.dy + r * 0.02)
        ..lineTo(o.dx + r * 0.5, o.dy - r * 0.25)
        ..lineTo(o.dx + r * 0.5, o.dy + r * 0.3)
        ..close();
      c.drawPath(p, Paint()..color = const Color(0xFF7A4E12));
      return;
    }
    drawDisc(c, o, r, pieces[v]);
    if (cb) drawMark(c, o, r, v);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final rules = TaflRules(s.cols);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)), Paint()..color = const Color(0xFF4F6B4A));
    for (var i = 0; i < s.cells.length; i++) {
      final r = _cell(s, size, i).deflate(1.2);
      var col = const Color(0xFFD8CFAE);
      if (rules.corner(i) || i == rules.center) col = const Color(0xFFB98A4A);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.1)), Paint()..color = col);
      if (s.last == i) c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.1)), Paint()..color = kHighlight.withValues(alpha: 0.35));
      final v = s.cells[i];
      if (v >= 0) _piece(c, r.center, r.width * 0.38, v, info.colorBlind);
      if (info.selected == i) _selectRing(c, r.center, r.width * 0.46);
      if (info.targets.contains(i)) drawTarget(c, r.center, r.width * 0.15);
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, r);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final w = size.width / s.cols;
    final c = (p.dx / w).floor(), r = (p.dy / w).floor();
    return s.inside(c, r) ? r * s.cols + c : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => _piece(c, r.center, r.width * 0.42, seat == 1 ? 2 : 0, info.colorBlind);
}

// ---------------------------------------------------------------- Havannah

/// Altıgen tahta (sivri tepeli hücreler).
class HexHexSkin extends BoardSkin {
  const HexHexSkin();

  @override
  double aspect(BoardState s) => 2 / math.sqrt(3);

  ({double u, Offset o}) _geo(GridState s, Size size) {
    final w = s.cols;
    final u = math.min(size.width / (w * math.sqrt(3) + 0.5), size.height / (1.5 * w + 0.6));
    return (u: u, o: Offset(size.width / 2, size.height / 2));
  }

  Offset _pos(GridState s, Size size, int i) {
    final g = _geo(s, size);
    final m = s.cols ~/ 2;
    final q = i % s.cols - m, r = i ~/ s.cols - m;
    return g.o + Offset(math.sqrt(3) * g.u * (q + r / 2), 1.5 * g.u * r);
  }

  Path _hex(Offset o, double u) {
    final p = Path();
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 6 + k * math.pi / 3;
      final pt = o + Offset(u * math.cos(a), u * math.sin(a));
      if (k == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    return p..close();
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final g = _geo(s, size);
    final rules = HavannahRules((s.cols + 1) ~/ 2);
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v == -2) continue;
      final o = _pos(s, size, i);
      final (corner, edge) = rules.cornerEdge(i);
      var col = const Color(0xFFE8DDC4);
      if (edge >= 0) col = const Color(0xFFD9C9A3);
      if (corner >= 0) col = const Color(0xFFC6A86C);
      c.drawPath(_hex(o, g.u * 0.97), Paint()..color = col);
      c.drawPath(
          _hex(o, g.u * 0.97),
          Paint()
            ..color = const Color(0x55000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (v >= 0) {
        drawDisc(c, o, g.u * 0.66, kBlackWhite[v]);
        if (info.colorBlind) drawMark(c, o, g.u * 0.66, v);
        if (s.last == i) _lastDot(c, o, g.u * 0.66);
      }
      if (info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: g.u * 0.8));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final g = _geo(s, size);
    var best = -1;
    var bd = g.u * 0.9;
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] == -2) continue;
      final d = (_pos(s, size, i) - p).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, kBlackWhite[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}
