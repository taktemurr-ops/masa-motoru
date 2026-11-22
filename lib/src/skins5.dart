import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'abstract3.dart';
import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'race2.dart';
import 'skins.dart';

const _two = [Color(0xFFD9534F), Color(0xFF2F6E9E)];

void _ring(Canvas c, Offset o, double r) => c.drawCircle(
    o,
    r,
    Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, r * 0.16));

void _text(Canvas c, String t, Offset center, double size, Color color, {FontWeight weight = FontWeight.w700}) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// Çubuk ya da zar sonucu: küçük rozet.
void _rollBadge(Canvas c, Offset o, double r, int value, Color color) {
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCircle(center: o, radius: r), Radius.circular(r * 0.3)), Paint()..color = Colors.white);
  c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCircle(center: o, radius: r), Radius.circular(r * 0.3)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12);
  _text(c, '$value', o, r * 1.1, color);
}

// ---------------------------------------------------------------- Mermer itme

class MarbleSkin extends BoardSkin {
  const MarbleSkin();
  static const marbles = [Color(0xFF2A2D34), Color(0xFFF2EEE4)];

  @override
  double aspect(BoardState s) => 2 / math.sqrt(3);

  ({double u, Offset o}) _geo(Size size) {
    final u = math.min(size.width / (9 * math.sqrt(3) + 0.6), size.height / (1.5 * 9 + 0.8));
    return (u: u, o: Offset(size.width / 2, size.height / 2));
  }

  Offset _pos(Size size, int i) {
    final g = _geo(size);
    final q = i % 9 - 4, r = i ~/ 9 - 4;
    return g.o + Offset(math.sqrt(3) * g.u * (q + r / 2), 1.5 * g.u * r);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final g = _geo(size);
    final board = Path();
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3;
      final pt = g.o + Offset(math.cos(a), math.sin(a)) * (g.u * 8.4);
      if (k == 0) {
        board.moveTo(pt.dx, pt.dy);
      } else {
        board.lineTo(pt.dx, pt.dy);
      }
    }
    c.drawPath(board..close(), Paint()..color = const Color(0xFF6E4B33));
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v == -2) continue;
      final o = _pos(size, i);
      c.drawCircle(o, g.u * 0.78, Paint()..color = const Color(0xFF4A3121));
      if (v >= 0) {
        drawDisc(c, o, g.u * 0.8, marbles[v]);
        if (info.colorBlind) drawMark(c, o, g.u * 0.8, v);
        if (s.last == i) c.drawCircle(o, g.u * 0.18, Paint()..color = kHighlight);
      }
      if (info.selected == i) _ring(c, o, g.u * 0.92);
      if (info.targets.contains(i)) drawTarget(c, o, g.u * 0.28);
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: g.u * 0.95));
    }
    // Düşürülen bilyeler: köşelerde sayaç.
    for (var p = 0; p < 2; p++) {
      final o = Offset(p == 0 ? g.u * 1.2 : size.width - g.u * 1.2, size.height - g.u * 1.2);
      drawDisc(c, o, g.u * 0.7, marbles[1 - p]);
      _text(c, '${s.vars[2 + p]}', o, g.u * 0.8, p == 0 ? Colors.black : Colors.white);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final g = _geo(size);
    var best = -1;
    var bd = g.u;
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] == -2) continue;
      final d = (_pos(size, i) - p).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, marbles[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}

// ---------------------------------------------------------------- Duvar yarışı

class WallRaceSkin extends BoardSkin {
  const WallRaceSkin();
  static const gap = 0.2;

  @override
  double aspect(BoardState s) => 1;

  double _u(GridState s, Size size) => size.width / s.cols;

  Rect _cell(GridState s, Size size, int i) {
    final u = _u(s, size);
    return Rect.fromLTWH((i % s.cols) * u + u * gap / 2, (i ~/ s.cols) * u + u * gap / 2, u * (1 - gap), u * (1 - gap));
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final n = s.cols, g = n - 1;
    final rules = WallRaceRules(n);
    final u = _u(s, size);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.2)), Paint()..color = const Color(0xFF5B4636));
    for (var i = 0; i < n * n; i++) {
      final r = _cell(s, size, i);
      final row = i ~/ n;
      var col = const Color(0xFFE9DCC2);
      if (row == 0) col = Color.lerp(col, _two[0], 0.22)!;
      if (row == n - 1) col = Color.lerp(col, _two[1], 0.22)!;
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.12)), Paint()..color = col);
      final v = s.cells[i];
      if (v >= 0) {
        drawDisc(c, r.center, r.width * 0.36, _two[v]);
        if (info.colorBlind) drawMark(c, r.center, r.width * 0.36, v);
      }
      if (info.selected == i) _ring(c, r.center, r.width * 0.44);
      if (info.targets.contains(i)) drawTarget(c, r.center, r.width * 0.14);
      if (info.hintTo == i) drawHint(c, r);
    }
    final wallPaint = [Paint()..color = const Color(0xFFB03A2E), Paint()..color = const Color(0xFF1F5E8C)];
    for (var k = 0; k < g * g; k++) {
      final r = k ~/ g, cc = k % g;
      final h = s.cells[rules.hIdx(r, cc)], v = s.cells[rules.vIdx(r, cc)];
      if (h >= 0) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cc * u + u * 0.06, (r + 1) * u - u * gap * 0.45, u * 1.88, u * gap * 0.9), Radius.circular(u * 0.05)), wallPaint[h]);
      }
      if (v >= 0) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((cc + 1) * u - u * gap * 0.45, r * u + u * 0.06, u * gap * 0.9, u * 1.88), Radius.circular(u * 0.05)), wallPaint[v]);
      }
      if (info.hintTo == rules.hIdx(r, cc) || info.hintTo == rules.vIdx(r, cc)) {
        drawTarget(c, Offset((cc + 1) * u, (r + 1) * u), u * 0.2);
      }
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final n = s.cols, g = n - 1;
    final rules = WallRaceRules(n);
    final u = _u(s, size);
    final fx = p.dx / u, fy = p.dy / u;
    final cx = fx.floor(), cy = fy.floor();
    if (cx < 0 || cy < 0 || cx >= n || cy >= n) return -1;
    final rx = fx - cx, ry = fy - cy;
    final inX = rx > gap / 2 && rx < 1 - gap / 2, inY = ry > gap / 2 && ry < 1 - gap / 2;
    if (inX && inY) return cy * n + cx;
    // Aralığa dokunma: yatay ya da dikey duvar yuvası.
    if (!inY) {
      final r = ry < 0.5 ? cy - 1 : cy;
      final c = (rx < 0.5 ? cx - 1 : cx).clamp(0, g - 1);
      if (r >= 0 && r < g) return rules.hIdx(r, c);
    }
    if (!inX) {
      final c = rx < 0.5 ? cx - 1 : cx;
      final r = (ry < 0.5 ? cy - 1 : cy).clamp(0, g - 1);
      if (c >= 0 && c < g) return rules.vIdx(r, c);
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, _two[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat);
  }
}

// ---------------------------------------------------------------- Ur

class UrSkin extends BoardSkin {
  const UrSkin();

  @override
  double aspect(BoardState s) => 8 / 4.4;

  /// Oyuncu yolundaki sıra → (sütun, satır). Oyuncu 0 alt sıra, 1 üst sıra.
  static (int, int) cellOf(int p, int pos) {
    final row = p == 0 ? 2 : 0;
    if (pos <= 4) return (4 - pos, row);
    if (pos <= 12) return (pos - 5, 1);
    return (20 - pos, row);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final u = size.width / 8;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.2)), Paint()..color = const Color(0xFF3B2A1E));
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 8; col++) {
        if (row != 1 && (col == 4 || col == 5)) continue;
        final r = Rect.fromLTWH(col * u + 2, row * u + 2, u - 4, u - 4);
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.1)), Paint()..color = const Color(0xFFE6D3A8));
        final rosette = (row != 1 && (col == 0 || col == 6)) || (row == 1 && col == 3);
        if (rosette) {
          for (var k = 0; k < 8; k++) {
            final a = k * math.pi / 4;
            c.drawCircle(r.center + Offset(math.cos(a), math.sin(a)) * u * 0.22, u * 0.09, Paint()..color = const Color(0xFF2F6E9E));
          }
          c.drawCircle(r.center, u * 0.1, Paint()..color = const Color(0xFFD9534F));
        }
      }
    }
    // Taşlar: yoldakiler karede, evdekiler ve bitenler alt/üst şeritte.
    for (var p = 0; p < 2; p++) {
      var homeN = 0, doneN = 0;
      for (var k = 0; k < 7; k++) {
        final idx = p * 7 + k;
        final v = s.cells[idx];
        Offset o;
        if (v == 0) {
          o = Offset((homeN++ + 0.5) * u * 0.55, u * (3.35 + p * 0.6));
        } else if (v == 15) {
          o = Offset(size.width - (doneN++ + 0.5) * u * 0.55, u * (3.35 + p * 0.6));
        } else {
          final (cc, rr) = cellOf(p, v);
          o = Offset((cc + 0.5) * u, (rr + 0.5) * u);
        }
        drawDisc(c, o, u * (v == 0 || v == 15 ? 0.2 : 0.32), _two[p]);
        if (info.colorBlind) drawMark(c, o, u * 0.3, p);
        if (info.targets.contains(idx) || info.hintTo == idx) _ring(c, o, u * 0.36);
      }
    }
    final roll = s.vars[1] - 1;
    if (roll >= 0) _rollBadge(c, Offset(u * 4.5, u * 0.5), u * 0.3, roll, _two[s.turn]);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final u = size.width / 8;
    final turn = s.turn;
    // Önce yoldaki taşlar, sonra ev şeridi.
    for (var k = 0; k < 7; k++) {
      final v = s.cells[turn * 7 + k];
      if (v <= 0 || v >= 15) continue;
      final (cc, rr) = cellOf(turn, v);
      if (Rect.fromLTWH(cc * u, rr * u, u, u).contains(p)) return turn * 7 + k;
    }
    if (p.dy > u * 3) {
      for (var k = 0; k < 7; k++) {
        if (s.cells[turn * 7 + k] == 0) return turn * 7 + k;
      }
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.42, _two[seat]);
}

// ---------------------------------------------------------------- Senet

class SenetSkin extends BoardSkin {
  const SenetSkin();

  @override
  double aspect(BoardState s) => 10 / 3.8;

  /// Kare (1..30) → (sütun, satır): yılan gibi.
  static (int, int) cellOf(int sq) {
    final i = sq - 1;
    final row = i ~/ 10;
    final col = row == 1 ? 9 - i % 10 : i % 10;
    return (col, row);
  }

  static const marks = {15: '☥', 26: '♡', 27: '≈', 28: 'III', 29: 'II', 30: 'I'};

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final u = size.width / 10;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.2)), Paint()..color = const Color(0xFF5C3A21));
    for (var sq = 1; sq <= 30; sq++) {
      final (col, row) = cellOf(sq);
      final r = Rect.fromLTWH(col * u + 2, row * u + 2, u - 4, u - 4);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.08)), Paint()..color = sq == 27 ? const Color(0xFF9CC7E0) : const Color(0xFFEAD9B0));
      final mk = marks[sq];
      if (mk != null) _text(c, mk, r.center, u * 0.34, const Color(0x996B4A22));
    }
    var off0 = 0, off1 = 0;
    for (var idx = 0; idx < 10; idx++) {
      final p = idx ~/ 5;
      final v = s.cells[idx];
      Offset o;
      if (v >= 31) {
        o = Offset(p == 0 ? (off0++ + 0.5) * u * 0.6 : size.width - (off1++ + 0.5) * u * 0.6, u * 3.4);
      } else {
        final (col, row) = cellOf(v);
        o = Offset((col + 0.5) * u, (row + 0.5) * u);
      }
      if (p == 0) {
        drawDisc(c, o, u * 0.3, _two[0]);
      } else {
        final cone = Path()
          ..moveTo(o.dx, o.dy - u * 0.32)
          ..lineTo(o.dx + u * 0.26, o.dy + u * 0.28)
          ..lineTo(o.dx - u * 0.26, o.dy + u * 0.28)
          ..close();
        c.drawPath(cone, Paint()..color = _two[1]);
      }
      if (info.targets.contains(idx) || info.hintTo == idx) _ring(c, o, u * 0.38);
    }
    final roll = s.vars[1] - 1;
    if (roll >= 0) _rollBadge(c, Offset(size.width / 2, u * 3.4), u * 0.28, roll, _two[s.turn]);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final u = size.width / 10;
    for (var k = 0; k < 5; k++) {
      final idx = s.turn * 5 + k;
      final v = s.cells[idx];
      if (v >= 31) continue;
      final (col, row) = cellOf(v);
      if (Rect.fromLTWH(col * u, row * u, u, u).contains(p)) return idx;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.42, _two[seat]);
}

// ---------------------------------------------------------------- Yut

class YutSkin extends BoardSkin {
  const YutSkin();

  @override
  double aspect(BoardState s) => 1 / 1.16;

  /// Durak → tahtadaki konum (0..1 birim kare).
  static Offset station(int i) {
    if (i < 20) {
      // 0 sağ alt, saat yönünün tersine: 0-5 sağ kenar yukarı, 5-10 üst kenar sola…
      final side = i ~/ 5, t = (i % 5) / 5;
      switch (side) {
        case 0:
          return Offset(1, 1 - t);
        case 1:
          return Offset(1 - t, 0);
        case 2:
          return Offset(0, t);
        default:
          return Offset(t, 1);
      }
    }
    const c = Offset(0.5, 0.5);
    switch (i) {
      case 20:
        return Offset.lerp(const Offset(1, 0), c, 1 / 3)!;
      case 21:
        return Offset.lerp(const Offset(1, 0), c, 2 / 3)!;
      case 22:
        return Offset.lerp(c, const Offset(0, 1), 1 / 3)!;
      case 23:
        return Offset.lerp(c, const Offset(0, 1), 2 / 3)!;
      case 24:
        return Offset.lerp(Offset.zero, c, 1 / 3)!;
      case 25:
        return Offset.lerp(Offset.zero, c, 2 / 3)!;
      case 26:
        return Offset.lerp(c, const Offset(1, 1), 1 / 3)!;
      case 27:
        return Offset.lerp(c, const Offset(1, 1), 2 / 3)!;
      default:
        return c;
    }
  }

  Offset _px(Size size, Offset unit) {
    final side = size.width * 0.84, m = size.width * 0.08;
    return Offset(m + unit.dx * side, m + unit.dy * side);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final u = size.width;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.04)), Paint()..color = const Color(0xFFF3E3C3));
    final line = Paint()
      ..color = const Color(0xFF8A6A45)
      ..strokeWidth = 2;
    c.drawRect(Rect.fromPoints(_px(size, Offset.zero), _px(size, const Offset(1, 1))), line..style = PaintingStyle.stroke);
    c.drawLine(_px(size, Offset.zero), _px(size, const Offset(1, 1)), line);
    c.drawLine(_px(size, const Offset(1, 0)), _px(size, const Offset(0, 1)), line);
    for (var i = 0; i < 29; i++) {
      final o = _px(size, station(i));
      final big = i % 5 == 0 && i < 20 || i == YutRules.center;
      c.drawCircle(o, u * (big ? 0.045 : 0.03), Paint()..color = big ? const Color(0xFF8A6A45) : Colors.white);
      c.drawCircle(
          o,
          u * (big ? 0.045 : 0.03),
          Paint()
            ..color = const Color(0xFF8A6A45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    // Taşlar (yığınlar üst üste kaydırılır).
    final counts = <int, int>{};
    for (var idx = 0; idx < 8; idx++) {
      final p = idx ~/ 4, k = idx % 4;
      final v = s.cells[idx];
      Offset o;
      if (v == YutRules.home) {
        o = Offset(u * (0.12 + k * 0.08) + (p == 1 ? u * 0.5 : 0), u * 1.08);
      } else if (v == YutRules.done) {
        o = Offset(u * (0.12 + k * 0.08) + (p == 1 ? u * 0.5 : 0), u * 1.13);
      } else {
        final n = counts.update(v * 2 + p, (x) => x + 1, ifAbsent: () => 0);
        o = _px(size, station(v)) + Offset(n * u * 0.012, -n * u * 0.012) + Offset(p == 0 ? -u * 0.012 : u * 0.012, 0);
      }
      drawDisc(c, o, u * (v == YutRules.done ? 0.02 : 0.032), _two[p]);
      if (info.colorBlind) drawMark(c, o, u * 0.03, p);
      if (info.targets.contains(idx) || info.hintTo == idx) _ring(c, o, u * 0.042);
    }
    final roll = s.vars[1] - 1;
    if (roll >= 0) {
      const names = ['', 'do', 'gae', 'geol', 'yut', 'mo'];
      _rollBadge(c, Offset(u * 0.5, u * 0.5), u * 0.05, roll, _two[s.turn]);
      _text(c, names[roll], Offset(u * 0.5, u * 0.58), u * 0.035, _two[s.turn]);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final u = size.width;
    final turn = s.turn;
    var best = -1;
    var bd = u * 0.06;
    for (var k = 0; k < 4; k++) {
      final idx = turn * 4 + k;
      final v = s.cells[idx];
      if (v == YutRules.done) continue;
      final o = v == YutRules.home ? Offset(u * (0.12 + k * 0.08) + (turn == 1 ? u * 0.5 : 0), u * 1.08) : _px(size, station(v));
      final d = (o - p).distance;
      if (d < bd) {
        bd = d;
        best = idx;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.42, _two[seat]);
}

// ---------------------------------------------------------------- Amiral battı

class NavalSkin extends BoardSkin {
  const NavalSkin();

  @override
  double aspect(BoardState s) => (s as GridState).cols / (s.cols * 2 + 0.6);

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final n = s.cols;
    final u = size.width / n;
    final me = info.human, them = 1 - me;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.2)), Paint()..color = const Color(0xFF0E2E47));
    void sea(int p, double top, bool hidden) {
      for (var i = 0; i < n * n; i++) {
        final r = Rect.fromLTWH((i % n) * u + 1, top + (i ~/ n) * u + 1, u - 2, u - 2);
        final v = s.cells[p * n * n + i];
        final ship = v % 8, shot = v >= 8;
        var col = const Color(0xFF1D5A85);
        if (ship != 7 && (!hidden || shot)) col = const Color(0xFF7D8A96);
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.12)), Paint()..color = col);
        if (shot) {
          if (ship != 7) {
            final x = Paint()
              ..color = const Color(0xFFE74C3C)
              ..strokeWidth = u * 0.12
              ..strokeCap = StrokeCap.round;
            c.drawLine(r.topLeft + Offset(u * 0.25, u * 0.25), r.bottomRight - Offset(u * 0.25, u * 0.25), x);
            c.drawLine(r.topRight + Offset(-u * 0.25, u * 0.25), r.bottomLeft + Offset(u * 0.25, -u * 0.25), x);
          } else {
            c.drawCircle(r.center, u * 0.12, Paint()..color = Colors.white70);
          }
        }
        if (p * n * n + i == s.last) c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.12)), Paint()..color = kHighlight.withValues(alpha: 0.35));
        if (info.hintTo == p * n * n + i) drawHint(c, r);
      }
    }

    sea(them, 0, true);
    sea(me, n * u + u * 0.6, false);
    c.drawLine(Offset(0, n * u + u * 0.3), Offset(size.width, n * u + u * 0.3), Paint()..color = Colors.white24);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final n = s.cols;
    final u = size.width / n;
    final c = (p.dx / u).floor(), r = (p.dy / u).floor();
    if (c < 0 || r < 0 || c >= n || r >= n) return -1;
    final them = 1 - (info?.human ?? 0);
    return them * n * n + r * n + c;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    c.drawRRect(RRect.fromRectAndRadius(r.deflate(r.width * 0.15), Radius.circular(r.width * 0.15)), Paint()..color = seat == 0 ? const Color(0xFF7D8A96) : const Color(0xFF1D5A85));
  }
}
