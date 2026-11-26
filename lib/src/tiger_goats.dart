import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'skins.dart';

// ======================================================================
// Kaplan ve Keçiler (Bagh-Chal, Nepal; Güney Asya'nın geleneksel av oyunu).
// 5×5 noktalı tahta; dik çizgiler ve (satır+sütun çift) noktalardan geçen
// çaprazlar. Koltuk 0 keçiler (önce oynar), koltuk 1 kaplanlar.
// Keçiler önce birer birer tahtaya konur, hepsi konunca yürür. Kaplanlar
// komşu boş noktaya yürür ya da bir keçinin üstünden çizgi boyunca atlayıp
// onu yakalar. [captureGoal] keçi yakalayan kaplanlar, bütün kaplanları
// kıpırdayamaz hâle getiren keçiler kazanır.
// Hücre: -1 boş, 0 keçi, 1 kaplan.
// vars: [0] bitti, [1] yakalamasız hamle sayacı, [2] konan keçi,
// [3] yakalanan keçi, [4] kazanan + 1.

class TigerGoatRules extends BoardRules<GridState> {
  /// Toplam keçi ve kaplanların kazanmak için yakalaması gereken keçi.
  final int goats, captureGoal;
  const TigerGoatRules({this.goats = 20, this.captureGoal = 5});

  @override
  String get id => 'tiger_goats';

  @override
  int get maxPly => 220;

  @override
  double get decisive => 70;

  static const n = 5;
  static const goat = 0, tiger = 1;

  static List<(int, int)> lines(int i) {
    final c = i % n, r = i ~/ n;
    return [(1, 0), (-1, 0), (0, 1), (0, -1), if ((r + c).isEven) ...[(1, 1), (-1, -1), (1, -1), (-1, 1)]];
  }

  static bool _in(int c, int r) => c >= 0 && r >= 0 && c < n && r < n;

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(n * n, -1);
    for (final i in const [0, 4, 20, 24]) {
      cells[i] = tiger;
    }
    return GridState(n, n, cells);
  }

  int goatsInHand(GridState s) => goats - s.vars[2];

  /// Kaplanın hamleleri: (hedef, yakalanan keçi ya da -1).
  static List<(int, int)> tigerSteps(GridState s, int from) {
    final out = <(int, int)>[];
    final c0 = from % n, r0 = from ~/ n;
    for (final (dc, dr) in lines(from)) {
      final c1 = c0 + dc, r1 = r0 + dr;
      if (!_in(c1, r1)) continue;
      final a = r1 * n + c1;
      if (s.cells[a] == -1) {
        out.add((a, -1));
      } else if (s.cells[a] == goat) {
        final c2 = c0 + 2 * dc, r2 = r0 + 2 * dr;
        if (_in(c2, r2) && s.cells[r2 * n + c2] == -1) out.add((r2 * n + c2, a));
      }
    }
    return out;
  }

  List<int> _gen(GridState s) {
    final out = <int>[];
    if (s.turn == goat) {
      if (goatsInHand(s) > 0) {
        for (var i = 0; i < n * n; i++) {
          if (s.cells[i] == -1) out.add(mv(-1, i));
        }
        return out;
      }
      for (var i = 0; i < n * n; i++) {
        if (s.cells[i] != goat) continue;
        for (final (dc, dr) in lines(i)) {
          final c = i % n + dc, r = i ~/ n + dr;
          if (_in(c, r) && s.cells[r * n + c] == -1) out.add(mv(i, r * n + c));
        }
      }
      return out;
    }
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] != tiger) continue;
      for (final (to, _) in tigerSteps(s, i)) {
        out.add(mv(i, to));
      }
    }
    return out;
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : _gen(s);

  @override
  int moveOrder(GridState s, int m) {
    if (s.turn == tiger) {
      final f = mvFrom(m), t = mvTo(m);
      final dc = (t % n - f % n).abs(), dr = (t ~/ n - f ~/ n).abs();
      return dc == 2 || dr == 2 ? 10 : 0;
    }
    return 0;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final f = mvFrom(m), t = mvTo(m);
    var captured = false;
    if (p == goat) {
      if (f < 0) {
        s.vars[2]++;
      } else {
        s.cells[f] = -1;
      }
      s.cells[t] = goat;
    } else {
      final dc = t % n - f % n, dr = t ~/ n - f ~/ n;
      if (dc.abs() == 2 || dr.abs() == 2) {
        s.cells[(f ~/ n + dr ~/ 2) * n + f % n + dc ~/ 2] = -1;
        s.vars[3]++;
        captured = true;
      }
      s.cells[f] = -1;
      s.cells[t] = tiger;
    }
    s.last = t;
    s.ply++;
    s.vars[1] = captured ? 0 : s.vars[1] + 1;
    s.turn = 1 - p;
    if (s.vars[3] >= captureGoal) {
      s.vars[0] = 1;
      s.vars[4] = tiger + 1;
    } else if (_gen(s).isEmpty) {
      s.vars[0] = 1;
      // Sırası gelen kıpırdayamıyorsa kaybeder.
      s.vars[4] = (1 - s.turn) + 1;
    } else if (s.vars[1] >= 80) {
      s.vars[0] = 1; // uzun süre yakalama olmadı: berabere
      s.vars[4] = 0;
    }
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) => isOver(s) ? s.vars[4] - 1 : -1;

  /// Kıpırdayabilen kaplan sayısı ve bütün kaplan hamleleri.
  static (int, int, int) tigerFreedom(GridState s) {
    var free = 0, all = 0, jumps = 0;
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] != tiger) continue;
      final st = tigerSteps(s, i);
      if (st.isNotEmpty) free++;
      all += st.length;
      for (final (_, cap) in st) {
        if (cap >= 0) jumps++;
      }
    }
    return (free, all, jumps);
  }

  @override
  double evaluate(GridState s, int player) {
    if (isOver(s)) {
      final w = winner(s);
      return w < 0 ? 0 : (w == player ? 99 : -99);
    }
    final (free, all, jumps) = tigerFreedom(s);
    // Kaplanlar açısından: yakalanan keçi, hareket alanı ve tehdit.
    var v = s.vars[3] * 16.0 + all * 1.2 + free * 3 + jumps * (s.turn == tiger ? 7 : 3.5) - (4 - free) * 6;
    // Keçilerin kenar ve köşelerde toplanması iyidir (çaprazsız noktalar güvenli).
    var safe = 0;
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] != goat) continue;
      final c = i % n, r = i ~/ n;
      if (c == 0 || r == 0 || c == n - 1 || r == n - 1) safe++;
    }
    v -= safe * 0.6;
    v = v - 30;
    return (player == tiger ? v : -v).clamp(-95, 95).toDouble();
  }

  @override
  String status(GridState s, String lang) {
    final hand = goatsInHand(s);
    return '${hand > 0 ? '◌ $hand  ·  ' : ''}✕ ${s.vars[3]}/$captureGoal';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

/// Kaplan ve Keçiler tahtası: kumaş üstüne işlenmiş çizgiler, keçiler krem
/// rengi boynuzlu taşlar, kaplanlar çizgili turuncu taşlar.
class TigerGoatSkin extends BoardSkin {
  const TigerGoatSkin();

  static const goatColor = Color(0xFFF3EBDD);
  static const tigerColor = Color(0xFFE07A1F);
  static const _cloth = Color(0xFF7A2E2A);
  static const _thread = Color(0xFFE9C46A);

  @override
  double aspect(BoardState s) => 1;

  Offset pos(Size size, int i) {
    final cw = size.width / TigerGoatRules.n, ch = size.height / TigerGoatRules.n;
    return Offset((i % TigerGoatRules.n + 0.5) * cw, (i ~/ TigerGoatRules.n + 0.5) * ch);
  }

  static void drawGoat(Canvas c, Offset o, double r) {
    drawDisc(c, o, r, goatColor);
    final horn = Paint()
      ..color = const Color(0xFF8A6A45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.14
      ..strokeCap = StrokeCap.round;
    // İki kıvrık boynuz ve yüz.
    c.drawArc(Rect.fromCircle(center: o.translate(-r * 0.32, -r * 0.42), radius: r * 0.3), math.pi * 0.9, math.pi * 0.8, false, horn);
    c.drawArc(Rect.fromCircle(center: o.translate(r * 0.32, -r * 0.42), radius: r * 0.3), math.pi * 1.3, math.pi * 0.8, false, horn);
    final eye = Paint()..color = const Color(0xFF3A2A1A);
    c.drawCircle(o.translate(-r * 0.22, -r * 0.02), r * 0.08, eye);
    c.drawCircle(o.translate(r * 0.22, -r * 0.02), r * 0.08, eye);
    c.drawOval(Rect.fromCenter(center: o.translate(0, r * 0.32), width: r * 0.36, height: r * 0.22), Paint()..color = const Color(0xFFD9B8A0));
  }

  static void drawTiger(Canvas c, Offset o, double r) {
    drawDisc(c, o, r, tigerColor);
    final stripe = Paint()
      ..color = const Color(0xFF2B1A10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round;
    for (final sx in const [-1.0, 1.0]) {
      c.drawLine(o.translate(sx * r * 0.85, -r * 0.2), o.translate(sx * r * 0.55, -r * 0.1), stripe);
      c.drawLine(o.translate(sx * r * 0.85, r * 0.15), o.translate(sx * r * 0.55, r * 0.12), stripe);
    }
    c.drawLine(o.translate(0, -r * 0.8), o.translate(0, -r * 0.5), stripe);
    c.drawLine(o.translate(-r * 0.22, -r * 0.75), o.translate(-r * 0.12, -r * 0.52), stripe);
    c.drawLine(o.translate(r * 0.22, -r * 0.75), o.translate(r * 0.12, -r * 0.52), stripe);
    final eye = Paint()..color = const Color(0xFFFFF3C4);
    c.drawOval(Rect.fromCenter(center: o.translate(-r * 0.26, -r * 0.12), width: r * 0.26, height: r * 0.16), eye);
    c.drawOval(Rect.fromCenter(center: o.translate(r * 0.26, -r * 0.12), width: r * 0.26, height: r * 0.16), eye);
    c.drawCircle(o.translate(0, r * 0.22), r * 0.1, Paint()..color = const Color(0xFF2B1A10));
    c.drawOval(Rect.fromCenter(center: o.translate(0, r * 0.45), width: r * 0.5, height: r * 0.26), Paint()..color = const Color(0xFFFFF3E0));
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    const n = TigerGoatRules.n;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    c.drawRRect(rr, Paint()..color = _cloth);
    // Kenar süsü: küçük baklavalar.
    final trim = Paint()..color = _thread.withValues(alpha: 0.35);
    final step = size.width / 20;
    for (var k = 0; k < 20; k++) {
      for (final y in [step * 0.4, size.height - step * 0.4]) {
        final o = Offset((k + 0.5) * step, y);
        c.drawPath(
            Path()
              ..moveTo(o.dx, o.dy - step * 0.25)
              ..lineTo(o.dx + step * 0.25, o.dy)
              ..lineTo(o.dx, o.dy + step * 0.25)
              ..lineTo(o.dx - step * 0.25, o.dy)
              ..close(),
            trim);
      }
    }
    final line = Paint()
      ..color = _thread
      ..strokeWidth = math.max(2, size.width * 0.008)
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r < n; r++) {
      c.drawLine(pos(size, r * n), pos(size, r * n + n - 1), line);
      c.drawLine(pos(size, r), pos(size, (n - 1) * n + r), line);
    }
    c.drawLine(pos(size, 0), pos(size, 24), line);
    c.drawLine(pos(size, 4), pos(size, 20), line);
    c.drawLine(pos(size, 2), pos(size, 10), line);
    c.drawLine(pos(size, 10), pos(size, 22), line);
    c.drawLine(pos(size, 22), pos(size, 14), line);
    c.drawLine(pos(size, 14), pos(size, 2), line);
    final rad = size.width / n * 0.34;
    for (var i = 0; i < n * n; i++) {
      final o = pos(size, i);
      final v = s.cells[i];
      if (v == TigerGoatRules.goat) {
        drawGoat(c, o, rad);
      } else if (v == TigerGoatRules.tiger) {
        drawTiger(c, o, rad);
      } else {
        c.drawCircle(o, rad * 0.2, Paint()..color = _thread);
      }
      if (v >= 0 && info.colorBlind) drawMark(c, o.translate(rad * 0.7, rad * 0.7), rad * 0.35, v);
      if (s.last == i && v >= 0) c.drawCircle(o.translate(0, -rad * 1.05), rad * 0.14, Paint()..color = kHighlight);
      if (info.selected == i) {
        c.drawCircle(
            o,
            rad * 1.15,
            Paint()
              ..color = const Color(0xFF4CAF50)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2, rad * 0.18));
      }
      if (info.targets.contains(i)) drawTarget(c, o, rad * 0.35);
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: rad * 1.2));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    const n = TigerGoatRules.n;
    final c = (p.dx / size.width * n).floor(), r = (p.dy / size.height * n).floor();
    return c >= 0 && r >= 0 && c < n && r < n ? r * n + c : -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    if (seat == TigerGoatRules.goat) {
      drawGoat(c, r.center, r.width * 0.42);
    } else {
      drawTiger(c, r.center, r.width * 0.42);
    }
  }
}
