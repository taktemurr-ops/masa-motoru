import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'conquest_game.dart';
import 'grid_state.dart';
import 'property_game.dart';
import 'settle_game.dart';
import 'skins.dart';
import 'skins_dice.dart';

const _groupColors = [
  Color(0xFF8E5B3B), Color(0xFF55B3D9), Color(0xFFC0508A), Color(0xFFE8892B), Color(0xFFD64541), Color(0xFF2F8F5B), Color(0xFF5C6370),
];

void _label(Canvas c, String t, Offset o, double size, Color color, {FontWeight w = FontWeight.w700}) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: w, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
}

/// Emlak ticareti: 7 × 7 çevre üzerinde 24 kare, ortada zarlar ve kasa.
class PropertySkin extends BoardSkin {
  const PropertySkin();

  static (int, int) cellPos(int i) {
    if (i <= 6) return (6 - i, 6);
    if (i <= 12) return (0, 6 - (i - 6));
    if (i <= 18) return (i - 12, 0);
    return (6, i - 18);
  }

  Rect _rect(Size size, int i) {
    final u = size.width / 7;
    final (x, y) = cellPos(i);
    return Rect.fromLTWH(x * u, y * u, u, u);
  }

  static const _icons = {0: '▶', 2: '?', 3: '%', 5: '☕'};

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final rules = PropertyRules(s.vars[14]);
    final u = size.width / 7;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFFDCE8D5));
    for (var i = 0; i < 24; i++) {
      final r = _rect(size, i).deflate(1.5);
      final sq = kPropBoard[i];
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)), Paint()..color = const Color(0xFFF8F5EC));
      if (sq.group >= 0) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.24), const Radius.circular(5)), Paint()..color = _groupColors[sq.group]);
      }
      final o = rules.owner(s, i);
      if (o >= 0) {
        c.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(5)),
            Paint()
              ..color = kPlayerColors[o]
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2.5, u * 0.06));
        for (var h = 0; h < rules.houses(s, i); h++) {
          c.drawRect(Rect.fromLTWH(r.left + r.width * (0.12 + h * 0.27), r.top + r.height * 0.04, r.width * 0.2, r.height * 0.16), Paint()..color = Colors.white);
        }
      }
      if (sq.kind == 1 || sq.kind == 4) {
        if (sq.kind == 4) _label(c, '⇆', Offset(r.center.dx, r.top + r.height * 0.5), u * 0.3, const Color(0xFF3A3F4A));
        _label(c, '${sq.price}', Offset(r.center.dx, r.top + r.height * (sq.kind == 4 ? 0.8 : 0.6)), u * 0.2, const Color(0xFF3A3F4A));
      } else {
        _label(c, _icons[sq.kind] ?? '', r.center, u * 0.36, const Color(0xFF3A3F4A));
        if (sq.kind == 3) _label(c, '-${sq.price}', Offset(r.center.dx, r.bottom - r.height * 0.18), u * 0.17, const Color(0xFFB3261E));
        if (sq.kind == 0) _label(c, '+${PropertyRules.passBonus}', Offset(r.center.dx, r.bottom - r.height * 0.18), u * 0.17, const Color(0xFF2F8F5B));
      }
      if (s.last == i) c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)), Paint()..color = kHighlight.withValues(alpha: 0.3));
      if (info.targets.contains(i) || info.hintTo == i) drawHint(c, r);
    }
    // Piyonlar.
    for (var p = 0; p < rules.n; p++) {
      if (!rules.alive(s, p)) continue;
      final r = _rect(size, rules.pos(s, p));
      final off = Offset((p % 2 - 0.5) * u * 0.36, (p ~/ 2 - 0.5) * u * 0.3 + u * 0.12);
      drawDisc(c, r.center + off, u * 0.13, kPlayerColors[p], ring: true);
    }
    // Orta: zarlar, oyuncuların kasası ve son şans kartı.
    final mid = Rect.fromLTWH(u * 1.2, u * 1.2, u * 4.6, u * 4.6);
    c.drawRRect(RRect.fromRectAndRadius(mid, Radius.circular(u * 0.3)), Paint()..color = Colors.white.withValues(alpha: 0.55));
    if (s.vars[2] > 0) {
      drawDie(c, Rect.fromCenter(center: mid.center + Offset(-u * 0.5, -u * 1.2), width: u * 0.8, height: u * 0.8), s.vars[2]);
      drawDie(c, Rect.fromCenter(center: mid.center + Offset(u * 0.5, -u * 1.2), width: u * 0.8, height: u * 0.8), s.vars[3]);
    }
    for (var p = 0; p < rules.n; p++) {
      final y = mid.center.dy + u * (0.05 + p * 0.55);
      final active = s.turn == p && !rules.isOver(s);
      drawDisc(c, Offset(mid.left + u * 1.1, y), u * 0.17, kPlayerColors[p], ring: active);
      _label(c, rules.alive(s, p) ? '${rules.money(s, p)}' : '—', Offset(mid.left + u * 2.3, y), u * 0.3, active ? const Color(0xFF1E2430) : const Color(0xFF5C6370), w: active ? FontWeight.w800 : FontWeight.w600);
    }
    final card = s.vars[13];
    if (card > 0) {
      const glyph = ['+100', '-60', '▶', '↶3', '+30×', '-20×'];
      _label(c, '? ${glyph[card - 1]}', Offset(mid.center.dx, mid.top + u * 0.35), u * 0.24, const Color(0xFF7A4B9A));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    for (var i = 0; i < 24; i++) {
      if (_rect(size, i).contains(p)) return i;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.36, kPlayerColors[seat], ring: true);
}

/// Dünya hâkimiyeti: deniz üzerinde beş ada, bölgeler sahip renginde ve
/// asker sayısıyla; deniz yolları kesikli çizgi.
class ConquestSkin extends BoardSkin {
  const ConquestSkin();
  static const _islands = [Color(0xFFCFE3B0), Color(0xFFE8D9A8), Color(0xFFD7CBB5), Color(0xFFBFD9C4), Color(0xFFE3C9B8)];

  Offset _p(Size size, int t) => Offset(kConquestPos[t].$1 * size.width, kConquestPos[t].$2 * size.height);

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final rules = ConquestRules(s.vars[10]);
    final u = size.width;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFF2F6E8E));
    // Dalgalar.
    final wave = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var y = 0.05; y < 1; y += 0.07) {
      final path = Path()..moveTo(0, y * size.height);
      for (var x = 0.0; x < 1; x += 0.05) {
        path.quadraticBezierTo((x + 0.025) * u, (y - 0.01) * size.height, (x + 0.05) * u, y * size.height);
      }
      c.drawPath(path, wave);
    }
    // Ada zeminleri.
    for (var t = 0; t < 18; t++) {
      c.drawCircle(_p(size, t), u * 0.11, Paint()..color = _islands[kConquestIsland[t]]);
    }
    final land = Paint()
      ..color = _islands[0]
      ..strokeWidth = u * 0.12
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in kConquestLand) {
      c.drawLine(_p(size, a), _p(size, b), land..color = _islands[kConquestIsland[a]]);
    }
    final link = Paint()
      ..color = const Color(0xFF5C4A32)
      ..strokeWidth = math.max(1.5, u * 0.005);
    for (final (a, b) in kConquestLand) {
      c.drawLine(_p(size, a), _p(size, b), link);
    }
    final sea = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = math.max(1.5, u * 0.005);
    for (final (a, b) in kConquestSea) {
      final pa = _p(size, a), pb = _p(size, b);
      const dashes = 9;
      for (var k = 0; k < dashes; k++) {
        if (k.isOdd) continue;
        c.drawLine(Offset.lerp(pa, pb, k / dashes)!, Offset.lerp(pa, pb, (k + 1) / dashes)!, sea);
      }
    }
    // Ada ödülleri.
    for (var isl = 0; isl < 5; isl++) {
      final ts = [for (var t = 0; t < 18; t++) if (kConquestIsland[t] == isl) t];
      var cx = 0.0, cy = 0.0;
      for (final t in ts) {
        cx += _p(size, t).dx;
        cy += _p(size, t).dy;
      }
      final o = Offset(cx / ts.length, cy / ts.length);
      _label(c, '+${kConquestBonus[isl]}', o, u * 0.035, const Color(0xFF5C4A32), w: FontWeight.w800);
    }
    final rad = u * 0.045;
    for (var t = 0; t < 18; t++) {
      final o = _p(size, t);
      final pl = rules.owner(s, t);
      if (s.last == t) c.drawCircle(o, rad * 1.35, Paint()..color = kHighlight.withValues(alpha: 0.7));
      drawDisc(c, o, rad, kPlayerColors[pl], ring: true);
      _label(c, '${rules.armies(s, t)}', o, rad * 0.95, Colors.white, w: FontWeight.w900);
      if (info.colorBlind) drawMark(c, o + Offset(rad * 0.9, -rad * 0.9), rad * 0.4, pl);
      if (info.selected == t) {
        c.drawCircle(
            o,
            rad * 1.3,
            Paint()
              ..color = const Color(0xFF4CAF50)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2.5, rad * 0.18));
      }
      if (info.targets.contains(t)) drawTarget(c, o, rad * 0.55);
      if (info.hintFrom == t || info.hintTo == t) drawHint(c, Rect.fromCircle(center: o, radius: rad * 1.3));
    }
    // Son saldırının zarları.
    if (s.vars[5] > 0) {
      final ds = u * 0.06;
      for (var k = 0; k < 3; k++) {
        if (s.vars[5 + k] > 0) drawDie(c, Rect.fromLTWH(u * (0.38 + k * 0.075), size.height * 0.02, ds, ds), s.vars[5 + k]);
      }
      for (var k = 0; k < 2; k++) {
        if (s.vars[8 + k] > 0) drawDie(c, Rect.fromLTWH(u * (0.38 + k * 0.075), size.height * 0.02 + ds * 1.2, ds, ds), s.vars[8 + k], face: const Color(0xFFFFE0E0));
      }
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    var best = -1;
    var bd = size.width * 0.08;
    for (var t = 0; t < 18; t++) {
      final d = (p - _p(size, t)).distance;
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.36, kPlayerColors[seat], ring: true);
}

/// Yerleşim kurma: altıgen ada, kaynak renkleri, sayı pulları, yollar ve
/// köyler; altta oyuncunun kaynakları (ver) ve bankadan alınacaklar (al).
class SettleSkin extends BoardSkin {
  const SettleSkin();
  static const resColors = [Color(0xFF2E7D32), Color(0xFFB5523B), Color(0xFF9CCC65), Color(0xFFF2C14E), Color(0xFF8D99AE), Color(0xFFE6D3A3)];
  static const resIcons = ['🌲', '🧱', '🐑', '🌾', '⛰', '🏜'];

  static const _boardH = 0.92, _rowH = 0.15;

  @override
  double aspect(BoardState s) => 1 / (_boardH + 2 * _rowH + 0.04);

  double _scale(Size size) => size.width / 9.4;
  Offset _pt(Size size, (double, double) q) {
    final sc = _scale(size);
    return Offset(size.width / 2 + q.$1 * sc, size.width * _boardH / 2 + q.$2 * sc);
  }

  Rect _btn(Size size, int row, int k) {
    final w = size.width / 5, top = size.width * (_boardH + 0.02 + row * _rowH);
    return Rect.fromLTWH(k * w, top, w, size.width * _rowH).deflate(4);
  }

  int _viewer(BoardPaintInfo? info) => (info?.human ?? 0) < 0 ? 0 : (info?.human ?? 0);

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final rules = SettleRules(s.vars[6], s.vars[7]);
    final geo = SettleGeo.i;
    final sc = _scale(size);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFF2F6E8E));
    for (var h = 0; h < 19; h++) {
      final path = Path();
      final vs = geo.hexVerts[h];
      for (var k = 0; k < 6; k++) {
        final o = _pt(size, geo.vertex[vs[k]]);
        if (k == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      final k = s.cells[SettleRules.hRes + h];
      c.drawPath(path, Paint()..color = resColors[k]);
      c.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFF3E6C8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, sc * 0.06));
      final ctr = _pt(size, geo.hexCenter[h]);
      _label(c, resIcons[k], ctr + Offset(0, -sc * 0.5), sc * 0.38, Colors.black);
      final num = s.cells[SettleRules.hNum + h];
      if (num > 0) {
        c.drawCircle(ctr + Offset(0, sc * 0.18), sc * 0.3, Paint()..color = const Color(0xFFF8F1DE));
        _label(c, '$num', ctr + Offset(0, sc * 0.14), sc * 0.27, num == 6 || num == 8 ? const Color(0xFFC0392B) : const Color(0xFF2B2E36), w: FontWeight.w800);
        final pc = SettleRules.pips(num);
        for (var d = 0; d < pc; d++) {
          c.drawCircle(ctr + Offset((d - (pc - 1) / 2) * sc * 0.07, sc * 0.36), sc * 0.022, Paint()..color = const Color(0xFF2B2E36));
        }
      }
      if (h == s.vars[4]) {
        final o = ctr + Offset(sc * 0.42, -sc * 0.1);
        c.drawCircle(o + Offset(0, -sc * 0.16), sc * 0.1, Paint()..color = const Color(0xFF1E2430));
        c.drawPath(
            Path()
              ..moveTo(o.dx - sc * 0.14, o.dy + sc * 0.16)
              ..lineTo(o.dx, o.dy - sc * 0.1)
              ..lineTo(o.dx + sc * 0.14, o.dy + sc * 0.16)
              ..close(),
            Paint()..color = const Color(0xFF1E2430));
      }
    }
    for (var e = 0; e < 72; e++) {
      final (a, b) = geo.edges[e];
      final pa = _pt(size, geo.vertex[a]), pb = _pt(size, geo.vertex[b]);
      final o = rules.eOwner(s, e);
      if (o >= 0) {
        c.drawLine(Offset.lerp(pa, pb, 0.15)!, Offset.lerp(pa, pb, 0.85)!,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.35)
              ..strokeWidth = sc * 0.2
              ..strokeCap = StrokeCap.round);
        c.drawLine(Offset.lerp(pa, pb, 0.15)!, Offset.lerp(pa, pb, 0.85)!,
            Paint()
              ..color = kPlayerColors[o]
              ..strokeWidth = sc * 0.13
              ..strokeCap = StrokeCap.round);
      }
      final mid = Offset.lerp(pa, pb, 0.5)!;
      if (info.targets.contains(SettleRules.edgeMove + e)) drawTarget(c, mid, sc * 0.1);
      if (info.hintTo == SettleRules.edgeMove + e) drawHint(c, Rect.fromCircle(center: mid, radius: sc * 0.25));
    }
    for (var v = 0; v < 54; v++) {
      final o = _pt(size, geo.vertex[v]);
      final ow = rules.vOwner(s, v);
      if (ow >= 0) {
        final big = rules.isCity(s, v);
        final w = sc * (big ? 0.38 : 0.28);
        final house = Path()
          ..moveTo(o.dx - w / 2, o.dy + w / 2)
          ..lineTo(o.dx - w / 2, o.dy - w * 0.05)
          ..lineTo(o.dx, o.dy - w / 2)
          ..lineTo(o.dx + w / 2, o.dy - w * 0.05)
          ..lineTo(o.dx + w / 2, o.dy + w / 2)
          ..close();
        if (big) house.addRect(Rect.fromLTWH(o.dx + w * 0.1, o.dy - w * 0.75, w * 0.3, w * 0.4));
        c.drawPath(house.shift(Offset(0, sc * 0.03)), Paint()..color = Colors.black.withValues(alpha: 0.35));
        c.drawPath(house, Paint()..color = kPlayerColors[ow]);
        c.drawPath(
            house,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, sc * 0.03));
        if (s.last == v) c.drawCircle(o, w * 0.75, Paint()..color = kHighlight.withValues(alpha: 0.35));
      }
      if (info.targets.contains(v)) drawTarget(c, o, sc * 0.12);
      if (info.hintTo == v) drawHint(c, Rect.fromCircle(center: o, radius: sc * 0.3));
    }
    // Kaynak paneli.
    final me = _viewer(info);
    for (var k = 0; k < 5; k++) {
      for (final row in const [0, 1]) {
        final r = _btn(size, row, k);
        final cell = (row == 0 ? SettleRules.giveCell : SettleRules.getCell) + k;
        final sel = info.selected == cell;
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = row == 0 ? resColors[k] : resColors[k].withValues(alpha: 0.45));
        if (sel) {
          c.drawRRect(
              RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(12)),
              Paint()
                ..color = const Color(0xFF4CAF50)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3);
        }
        _label(c, resIcons[k], Offset(r.center.dx - r.width * 0.18, r.center.dy), r.height * 0.42, Colors.black);
        _label(c, row == 0 ? '${rules.res(s, me, k)}' : '+1', Offset(r.center.dx + r.width * 0.2, r.center.dy), r.height * 0.38, Colors.white, w: FontWeight.w900);
        if (info.targets.contains(cell)) drawTarget(c, r.topRight + Offset(-r.height * 0.15, r.height * 0.15), r.height * 0.1);
        if (info.hintFrom == cell || info.hintTo == cell) drawHint(c, r);
      }
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    for (final row in const [0, 1]) {
      for (var k = 0; k < 5; k++) {
        if (_btn(size, row, k).contains(p)) return (row == 0 ? SettleRules.giveCell : SettleRules.getCell) + k;
      }
    }
    final geo = SettleGeo.i;
    final sc = _scale(size);
    var best = -1;
    var bd = sc * 0.45;
    for (var v = 0; v < 54; v++) {
      final d = (p - _pt(size, geo.vertex[v])).distance;
      if (d < bd) {
        bd = d;
        best = v;
      }
    }
    for (var e = 0; e < 72; e++) {
      final (a, b) = geo.edges[e];
      final mid = Offset.lerp(_pt(size, geo.vertex[a]), _pt(size, geo.vertex[b]), 0.5)!;
      final d = (p - mid).distance;
      if (d < bd) {
        bd = d;
        best = SettleRules.edgeMove + e;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.36, kPlayerColors[seat], ring: true);
}
