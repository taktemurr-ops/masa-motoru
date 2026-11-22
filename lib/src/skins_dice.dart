import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'dice_games.dart';
import 'grid_state.dart';
import 'race_games.dart';
import 'skins.dart';

const kPlayerColors = [Color(0xFFD64541), Color(0xFF2E86DE), Color(0xFF27AE60), Color(0xFFE5B712)];

/// Zar yüzü çizimi.
void drawDie(Canvas c, Rect r, int v, {bool held = false, bool dim = false, Color face = Colors.white}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.2));
  c.drawRRect(rr.shift(Offset(0, r.width * 0.05)), Paint()..color = Colors.black.withValues(alpha: 0.25));
  c.drawRRect(rr, Paint()..color = dim ? face.withValues(alpha: 0.45) : face);
  if (held) {
    c.drawRRect(
        rr.inflate(2),
        Paint()
          ..color = kHighlight
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, r.width * 0.07));
  }
  if (v < 1 || v > 6) return;
  final dot = Paint()..color = const Color(0xFF2B2E36);
  const pos = {
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
  };
  for (final (x, y) in pos[v]!) {
    c.drawCircle(Offset(r.left + x * r.width, r.top + y * r.height), r.width * 0.09, dot);
  }
}

void drawText(Canvas c, String s, Offset center, double size, Color color, {FontWeight w = FontWeight.w800}) {
  final t = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: w, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  t.paint(c, center - Offset(t.width / 2, t.height / 2));
}

/// Simge düğmesi: yeniden at (döner ok), kasa (kilit), yalan (ünlem).
void drawButton(Canvas c, Rect r, String kind, bool enabled, {bool hint = false}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.3));
  c.drawRRect(rr, Paint()..color = enabled ? const Color(0xFF2F7D5B) : const Color(0x332F7D5B));
  if (hint) {
    c.drawRRect(
        rr.inflate(2),
        Paint()
          ..color = kHighlight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }
  final o = r.center;
  final s = r.height * 0.28;
  final pen = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.28
    ..strokeCap = StrokeCap.round;
  switch (kind) {
    case 'reroll':
      c.drawArc(Rect.fromCircle(center: o, radius: s), -math.pi * 0.2, math.pi * 1.6, false, pen);
      final tip = o + Offset(math.cos(-math.pi * 0.2) * s, math.sin(-math.pi * 0.2) * s);
      c.drawLine(tip, tip + Offset(-s * 0.55, -s * 0.05), pen);
      c.drawLine(tip, tip + Offset(s * 0.05, s * 0.55), pen);
    case 'bank':
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o + Offset(0, s * 0.3), width: s * 1.7, height: s * 1.2), Radius.circular(s * 0.2)), pen);
      c.drawArc(Rect.fromCenter(center: o - Offset(0, s * 0.3), width: s * 1.1, height: s * 1.2), math.pi, math.pi, false, pen);
    default:
      drawText(c, '!', o, r.height * 0.6, Colors.white);
  }
}

// ---------------------------------------------------------------- Kızma Birader

class KizmaSkin extends BoardSkin {
  final KizmaRules rules;
  const KizmaSkin(this.rules);

  static const track = [
    (4, 10), (4, 9), (4, 8), (4, 7), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6), (0, 5), //
    (0, 4), (1, 4), (2, 4), (3, 4), (4, 4), (4, 3), (4, 2), (4, 1), (4, 0), (5, 0), //
    (6, 0), (6, 1), (6, 2), (6, 3), (6, 4), (7, 4), (8, 4), (9, 4), (10, 4), (10, 5), //
    (10, 6), (9, 6), (8, 6), (7, 6), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10), (5, 10),
  ];
  static const homes = [
    [(5, 9), (5, 8), (5, 7), (5, 6)],
    [(1, 5), (2, 5), (3, 5), (4, 5)],
    [(5, 1), (5, 2), (5, 3), (5, 4)],
    [(9, 5), (8, 5), (7, 5), (6, 5)],
  ];
  static const bases = [
    [(0, 9), (1, 9), (0, 10), (1, 10)],
    [(0, 0), (1, 0), (0, 1), (1, 1)],
    [(9, 0), (10, 0), (9, 1), (10, 1)],
    [(9, 9), (10, 9), (9, 10), (10, 10)],
  ];

  @override
  double aspect(BoardState s) => 1;

  (int, int) _pos(GridState s, int idx) {
    final p = idx ~/ 4, k = idx % 4;
    final v = s.cells[idx];
    if (v < 0) return bases[p][k];
    if (v >= 40) return homes[p][v - 40];
    return track[(p * 10 + v) % 40];
  }

  Offset _c(Size size, (int, int) xy) {
    final u = size.width / 11;
    return Offset((xy.$1 + 0.5) * u, (xy.$2 + 0.5) * u);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final u = size.width / 11;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.4)), Paint()..color = const Color(0xFFF6EBD2));
    final ring = Paint()
      ..color = const Color(0xFF6B5B45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 40; i++) {
      final o = _c(size, track[i]);
      final start = i % 10 == 0 ? kPlayerColors[i ~/ 10] : Colors.white;
      c.drawCircle(o, u * 0.4, Paint()..color = start);
      c.drawCircle(o, u * 0.4, ring);
    }
    for (var p = 0; p < 4; p++) {
      final col = p < rules.count ? kPlayerColors[p] : const Color(0xFFCCCCCC);
      for (final xy in [...homes[p], ...bases[p]]) {
        final o = _c(size, xy);
        c.drawCircle(o, u * 0.4, Paint()..color = col.withValues(alpha: 0.35));
        c.drawCircle(o, u * 0.4, ring);
      }
    }
    for (var idx = 0; idx < rules.count * 4; idx++) {
      final o = _c(size, _pos(s, idx));
      final p = idx ~/ 4;
      drawDisc(c, o, u * 0.33, kPlayerColors[p], ring: true);
      if (info.colorBlind) drawText(c, '${p + 1}', o, u * 0.35, Colors.white);
      if (info.hintTo == idx) drawHint(c, Rect.fromCircle(center: o, radius: u * 0.45));
    }
    if (info.canAct) {
      for (final m in rules.moves(s)) {
        if (m == kPass) continue;
        drawTarget(c, _c(size, _pos(s, mvTo(m))), u * 0.12);
      }
    }
    final die = s.vars[1];
    final dr = Rect.fromCenter(center: size.center(Offset.zero), width: u * 0.9, height: u * 0.9);
    drawDie(c, dr, die, face: die == 0 ? const Color(0xFFEEEEEE) : Colors.white);
    c.drawCircle(dr.center + Offset(0, -u * 0.8), u * 0.15, Paint()..color = kPlayerColors[s.turn]);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final u = size.width / 11;
    final human = info?.human ?? 0;
    for (var k = 0; k < 4; k++) {
      final idx = human * 4 + k;
      if ((_c(size, _pos(s, idx)) - p).distance < u * 0.5) return idx;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, kPlayerColors[seat]);
}

// ---------------------------------------------------------------- Yılan merdiven

class SnakesSkin extends BoardSkin {
  final SnakesRules rules;
  const SnakesSkin(this.rules);

  @override
  double aspect(BoardState s) => 10 / 11.4;

  Offset _sq(Size size, int n) {
    final u = size.width / 10;
    if (n <= 0) return Offset(-u * 0.2 + u * 0.5, u * 10 - u * 0.5);
    final i = n - 1;
    final row = i ~/ 10, col = row.isEven ? i % 10 : 9 - i % 10;
    return Offset((col + 0.5) * u, (9 - row + 0.5) * u);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final u = size.width / 10;
    for (var n = 1; n <= 100; n++) {
      final o = _sq(size, n);
      final light = ((n - 1) ~/ 10 + (n - 1) % 10).isEven;
      c.drawRect(Rect.fromCenter(center: o, width: u, height: u), Paint()..color = light ? const Color(0xFFF7EBD0) : const Color(0xFFE8D3A6));
      drawText(c, '$n', o + Offset(-u * 0.28, -u * 0.3), u * 0.2, const Color(0x996B5B45), w: FontWeight.w600);
    }
    for (var a = 1; a <= 100; a++) {
      final b = s.cells[4 + a];
      if (b < 0) continue;
      final pa = _sq(size, a), pb = _sq(size, b);
      if (b > a) {
        // Merdiven: iki ray ve basamaklar.
        final d = pb - pa;
        final nrm = Offset(-d.dy, d.dx) / d.distance * u * 0.16;
        final rail = Paint()
          ..color = const Color(0xFF8A5A33)
          ..strokeWidth = u * 0.07
          ..strokeCap = StrokeCap.round;
        c.drawLine(pa + nrm, pb + nrm, rail);
        c.drawLine(pa - nrm, pb - nrm, rail);
        final steps = (d.distance / (u * 0.35)).floor();
        for (var k = 1; k < steps; k++) {
          final q = pa + d * (k / steps);
          c.drawLine(q + nrm, q - nrm, rail..strokeWidth = u * 0.05);
        }
      } else {
        // Yılan: dalgalı gövde.
        final d = pb - pa;
        final nrm = Offset(-d.dy, d.dx) / d.distance;
        final path = Path()..moveTo(pa.dx, pa.dy);
        const seg = 24;
        for (var k = 1; k <= seg; k++) {
          final t = k / seg;
          final q = pa + d * t + nrm * math.sin(t * math.pi * 4) * u * 0.25;
          path.lineTo(q.dx, q.dy);
        }
        c.drawPath(
            path,
            Paint()
              ..color = const Color(0xCC2F9E62)
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.16
              ..strokeCap = StrokeCap.round);
        c.drawCircle(pa, u * 0.15, Paint()..color = const Color(0xFF1F7A4A));
        c.drawCircle(pa + Offset(u * 0.05, -u * 0.04), u * 0.035, Paint()..color = Colors.white);
      }
    }
    for (var p = 0; p < rules.count; p++) {
      final o = _sq(size, s.cells[p]) + Offset((p % 2 - 0.5) * u * 0.32, (p ~/ 2 - 0.5) * u * 0.32);
      drawDisc(c, o, u * 0.2, kPlayerColors[p], ring: true);
    }
    // Zarlar.
    final dy = u * 10 + u * 0.7;
    for (var k = 0; k < 2; k++) {
      final r = Rect.fromCenter(center: Offset(size.width / 2 + (k == 0 ? -u * 0.8 : u * 0.8), dy), width: u * 1.1, height: u * 1.1);
      final v = s.vars[1 + k];
      drawDie(c, r, v, held: info.hintTo == k, dim: v == 0);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]) {
    final u = size.width / 10;
    if (p.dy < u * 10) return -1;
    return p.dx < size.width / 2 ? 0 : 1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, kPlayerColors[seat]);
}

// ---------------------------------------------------------------- Zar beşlisi

class ZarBesliSkin extends BoardSkin {
  const ZarBesliSkin();
  static const rules = ZarBesliRules();
  static const labels = ['', '', '', '', '', '', '3×', '4×', '3+2', '▭4', '▭5', '5×', 'Σ'];

  @override
  double aspect(BoardState s) => 1 / 1.45;

  Rect _die(Size size, int i) {
    final w = size.width / 6.2;
    return Rect.fromLTWH(w * 0.35 + i * w * 1.1, w * 0.25, w, w);
  }

  Rect _reroll(Size size) {
    final w = size.width / 6.2;
    return Rect.fromLTWH(size.width * 0.3, w * 1.45, size.width * 0.4, w * 0.7);
  }

  Rect _row(Size size, int k) {
    final top = size.width / 6.2 * 2.35;
    final h = (size.height - top) / 13;
    return Rect.fromLTWH(0, top + k * h, size.width, h);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..color = const Color(0xFF1E5B46));
    final rolled = s.vars[1] > 0;
    for (var i = 0; i < 5; i++) {
      drawDie(c, _die(size, i), rolled ? s.cells[i] : 0, held: s.vars[2] & (1 << i) != 0 || info.hintTo == kToggleBase + i, dim: !rolled);
    }
    final rr = _reroll(size);
    drawButton(c, rr, 'reroll', rolled && s.vars[1] < 3 && info.canAct, hint: info.hintTo == kReroll);
    for (var k = 0; k < 3; k++) {
      c.drawCircle(Offset(rr.right + 14 + k * 12, rr.center.dy), 4, Paint()..color = k < s.vars[1] ? Colors.white38 : Colors.white);
    }
    final me = info.human, op = 1 - info.human;
    for (var k = 0; k < 13; k++) {
      final r = _row(size, k);
      if (k.isEven) c.drawRect(r, Paint()..color = const Color(0x14FFFFFF));
      final lab = Rect.fromLTWH(r.left + 8, r.top + r.height * 0.12, r.height * 0.76, r.height * 0.76);
      if (k < 6) {
        drawDie(c, lab, k + 1);
      } else {
        drawText(c, labels[k], lab.center + Offset(r.height * 0.3, 0), r.height * 0.42, Colors.white);
      }
      final mine = s.cells[rules.slot(me, k)], theirs = s.cells[rules.slot(op, k)];
      final cx1 = size.width * 0.58, cx2 = size.width * 0.84;
      if (mine >= 0) {
        drawText(c, '$mine', Offset(cx1, r.center.dy), r.height * 0.5, Colors.white);
      } else if (rolled && s.turn == me) {
        final pot = ZarBesliRules.score(rules.dice(s), k);
        drawText(c, '$pot', Offset(cx1, r.center.dy), r.height * 0.46, const Color(0xFFFFD86B), w: FontWeight.w600);
      }
      if (theirs >= 0) drawText(c, '$theirs', Offset(cx2, r.center.dy), r.height * 0.5, Colors.white70);
      if (info.hintTo == kScoreBase + k) drawHint(c, r);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]) {
    for (var i = 0; i < 5; i++) {
      if (_die(size, i).inflate(4).contains(p)) return kToggleBase + i;
    }
    if (_reroll(size).inflate(6).contains(p)) return kReroll;
    for (var k = 0; k < 13; k++) {
      if (_row(size, k).contains(p)) return kScoreBase + k;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDie(c, r.deflate(2), seat == 0 ? 5 : 2);
}

// ---------------------------------------------------------------- Farkle

class FarkleSkin extends BoardSkin {
  const FarkleSkin();

  @override
  double aspect(BoardState s) => 1 / 0.9;

  Rect _die(Size size, int i) {
    final w = size.width / 4;
    return Rect.fromLTWH(w * 0.3 + (i % 3) * w * 1.15, size.height * 0.08 + (i ~/ 3) * w * 1.15, w * 0.9, w * 0.9);
  }

  Rect _btn(Size size, int k) => Rect.fromLTWH(size.width * (k == 0 ? 0.08 : 0.54), size.height * 0.74, size.width * 0.38, size.height * 0.18);

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..color = const Color(0xFF6B2E2E));
    for (var i = 0; i < 6; i++) {
      final st2 = s.cells[6 + i];
      drawDie(c, _die(size, i), s.vars[1] == 1 && st2 != 1 ? 0 : s.cells[i], held: st2 == 2 || info.hintTo == kToggleBase + i, dim: st2 == 1);
    }
    final ok = info.canAct && FarkleRules.scoreOf([for (var i = 0; i < 6; i++) if (s.cells[6 + i] == 2) s.cells[i]]) > 0;
    drawButton(c, _btn(size, 0), 'reroll', ok, hint: info.hintTo == kReroll);
    drawButton(c, _btn(size, 1), 'bank', ok, hint: info.hintTo == kBank);
  }

  @override
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]) {
    for (var i = 0; i < 6; i++) {
      if (_die(size, i).inflate(4).contains(p)) return kToggleBase + i;
    }
    if (_btn(size, 0).contains(p)) return kReroll;
    if (_btn(size, 1).contains(p)) return kBank;
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDie(c, r.deflate(2), seat == 0 ? 1 : 5);
}

// ---------------------------------------------------------------- Yalancı zarı

class LiarSkin extends BoardSkin {
  final LiarRules rules;
  const LiarSkin(this.rules);

  @override
  double aspect(BoardState s) => 1 / 1.25;

  Rect _bidCell(Size size, int row, int face) {
    final top = size.height * 0.42;
    final w = size.width / 6, h = (size.height * 0.46) / 6;
    return Rect.fromLTWH(w * 0.5 + (face - 2) * w, top + row * h, w * 0.92, h * 0.88);
  }

  Rect _liar(Size size) => Rect.fromLTWH(size.width * 0.3, size.height * 0.89, size.width * 0.4, size.height * 0.1);

  int _baseQ(GridState s) => s.vars[1] == 0 ? 1 : s.vars[1] ~/ 10;

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..color = const Color(0xFF2E3F6B));
    final me = info.human;
    final w = size.width / 6.4;
    // Benim zarlarım.
    for (var k = 0; k < 5; k++) {
      final v = s.cells[me * 5 + k];
      if (v == 0) continue;
      drawDie(c, Rect.fromLTWH(w * 0.4 + k * w * 1.15, size.height * 0.04, w, w), s.vars[3] == 1 ? 0 : v);
    }
    // Rakipler: bardak ve zar sayısı.
    var x = 0;
    for (var p = 0; p < rules.count; p++) {
      if (p == me) continue;
      final o = Offset(size.width * (0.2 + x * 0.3), size.height * 0.24);
      c.drawPath(
          Path()
            ..moveTo(o.dx - w * 0.5, o.dy + w * 0.4)
            ..lineTo(o.dx - w * 0.35, o.dy - w * 0.4)
            ..lineTo(o.dx + w * 0.35, o.dy - w * 0.4)
            ..lineTo(o.dx + w * 0.5, o.dy + w * 0.4)
            ..close(),
          Paint()..color = kPlayerColors[p]);
      drawText(c, '${rules.diceOf(s, p)}', o, w * 0.45, Colors.white);
      if (s.turn == p) c.drawCircle(o + Offset(0, w * 0.62), 4, Paint()..color = kHighlight);
      x++;
    }
    // Masadaki teklif.
    final bid = s.vars[1];
    if (bid > 0) {
      drawText(c, '${bid ~/ 10} ×', Offset(size.width * 0.78, size.height * 0.24), w * 0.45, Colors.white);
      drawDie(c, Rect.fromCenter(center: Offset(size.width * 0.9, size.height * 0.24), width: w * 0.6, height: w * 0.6), bid % 10);
    }
    // Teklif ızgarası.
    final q0 = _baseQ(s);
    for (var row = 0; row < 6; row++) {
      final q = q0 + row;
      if (q > rules.totalDice(s)) break;
      for (var f = 2; f <= 6; f++) {
        final r = _bidCell(size, row, f);
        final code = q * 10 + f;
        final legal = info.canAct && code > bid;
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = legal ? const Color(0x33FFFFFF) : const Color(0x0FFFFFFF));
        drawText(c, '$q', r.centerLeft + Offset(r.width * 0.22, 0), r.height * 0.45, legal ? Colors.white : Colors.white30);
        drawDie(c, Rect.fromLTWH(r.right - r.height * 0.85, r.top + r.height * 0.12, r.height * 0.76, r.height * 0.76), f, dim: !legal);
        if (info.hintTo == code) drawHint(c, r);
      }
    }
    drawButton(c, _liar(size), 'liar', info.canAct && bid > 0, hint: info.hintTo == LiarRules.kLiar);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    if (_liar(size).contains(p)) return LiarRules.kLiar;
    final q0 = _baseQ(s);
    for (var row = 0; row < 6; row++) {
      for (var f = 2; f <= 6; f++) {
        if (_bidCell(size, row, f).contains(p)) return (q0 + row) * 10 + f;
      }
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, kPlayerColors[seat]);
}
