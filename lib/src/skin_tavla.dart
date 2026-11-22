import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'skins.dart';
import 'tavla.dart';

/// Tavla tahtası: 24 üçgen, ortada kırık bölmesi, sağda toplama yeri.
class TavlaSkin extends BoardSkin {
  const TavlaSkin();
  static const rules = TavlaRules();

  static const felt = Color(0xFF2F5D47);
  static const frame = Color(0xFF6B4226);
  static const triA = Color(0xFFE6CFA0), triB = Color(0xFFA9452F);
  static const pieces = [Color(0xFFF3ECDD), Color(0xFF2B2E36)];

  @override
  double aspect(BoardState s) => 14 / 10.5;

  double _u(Size size) => size.width / 14;

  int _col(int i) {
    final k = i < 12 ? 11 - i : i - 12;
    return k < 6 ? k : k + 1;
  }

  bool _top(int i) => i >= 12;

  Rect _pointRect(Size size, int i) {
    final u = _u(size);
    final h = size.height;
    final x = _col(i) * u;
    return _top(i) ? Rect.fromLTWH(x, 0, u, h * 0.45) : Rect.fromLTWH(x, h * 0.55, u, h * 0.45);
  }

  void _checker(Canvas c, Offset o, double r, int p, bool cb) {
    drawDisc(c, o, r, pieces[p], ring: true);
    if (cb) drawMark(c, o, r, p);
  }

  void _stack(Canvas c, Rect area, bool fromTop, int count, int p, bool cb, {int pinned = -1}) {
    if (count <= 0 && pinned < 0) return;
    final r = area.width * 0.44;
    final maxShown = 5;
    final step = math.min(r * 2, (area.height - r * 2) / math.max(1, math.min(count, maxShown) - 1 + (pinned >= 0 ? 1 : 0)));
    var k = 0;
    Offset at(int j) => fromTop ? Offset(area.center.dx, area.top + r + j * step) : Offset(area.center.dx, area.bottom - r - j * step);
    if (pinned >= 0) {
      _checker(c, at(0), r, pinned, cb);
      k = 1;
    }
    for (var j = 0; j < math.min(count, maxShown); j++) {
      _checker(c, at(k + j), r, p, cb);
    }
    if (count > maxShown) {
      final t = TextPainter(
        text: TextSpan(text: '$count', style: TextStyle(fontSize: r, fontWeight: FontWeight.w800, color: p == 0 ? Colors.black87 : Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(c, at(k + maxShown - 1) - Offset(t.width / 2, t.height / 2));
    }
  }

  void _die(Canvas c, Rect r, int v, bool used) {
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.18)), Paint()..color = used ? const Color(0x88FFFFFF) : Colors.white);
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

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as TavlaState;
    final u = _u(size);
    final h = size.height;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.3)), Paint()..color = frame);
    c.drawRect(Rect.fromLTWH(0, 0, u * 13, h).deflate(u * 0.08), Paint()..color = felt);
    c.drawRect(Rect.fromLTWH(u * 6, 0, u, h), Paint()..color = frame);
    c.drawRect(Rect.fromLTWH(u * 13, 0, u, h).deflate(u * 0.1), Paint()..color = const Color(0xFF4A2E1A));
    for (var i = 0; i < 24; i++) {
      final r = _pointRect(size, i);
      final tri = Path();
      if (_top(i)) {
        tri
          ..moveTo(r.left + u * 0.05, r.top)
          ..lineTo(r.right - u * 0.05, r.top)
          ..lineTo(r.center.dx, r.bottom - u * 0.2);
      } else {
        tri
          ..moveTo(r.left + u * 0.05, r.bottom)
          ..lineTo(r.right - u * 0.05, r.bottom)
          ..lineTo(r.center.dx, r.top + u * 0.2);
      }
      c.drawPath(tri..close(), Paint()..color = i % 2 == 0 ? triA : triB);
      final v = s.cells[i];
      final pinned = s.pins[i] != 0 ? (s.pins[i] > 0 ? 0 : 1) : -1;
      _stack(c, r, _top(i), v.abs(), v > 0 ? 0 : 1, info.colorBlind, pinned: pinned);
      if (info.selected == i) drawHint(c, r);
      if (info.targets.contains(i)) drawTarget(c, _top(i) ? Offset(r.center.dx, r.bottom - u * 0.3) : Offset(r.center.dx, r.top + u * 0.3), u * 0.18);
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, r);
    }
    // Kırıklar ve toplananlar.
    final barTop = Rect.fromLTWH(u * 6, 0, u, h * 0.45), barBot = Rect.fromLTWH(u * 6, h * 0.55, u, h * 0.45);
    _stack(c, barTop, true, s.cells[TavlaRules.bar0], 0, info.colorBlind);
    _stack(c, barBot, false, s.cells[TavlaRules.bar1], 1, info.colorBlind);
    final offTop = Rect.fromLTWH(u * 13, 0, u, h * 0.45), offBot = Rect.fromLTWH(u * 13, h * 0.55, u, h * 0.45);
    _stack(c, offBot, false, s.cells[TavlaRules.off0], 0, info.colorBlind);
    _stack(c, offTop, true, s.cells[TavlaRules.off1], 1, info.colorBlind);
    if (info.selected == TavlaRules.bar0 || info.selected == TavlaRules.bar1) drawHint(c, info.selected == TavlaRules.bar0 ? barTop : barBot);
    if (info.targets.contains(TavlaRules.off0) || info.targets.contains(TavlaRules.off1)) {
      drawTarget(c, (info.targets.contains(TavlaRules.off0) ? offBot : offTop).center, u * 0.25);
    }
    // Zarlar: sağ yarının ortası.
    final dice = rules.dice(s);
    final dw = u * 0.8;
    for (var k = 0; k < dice.length; k++) {
      _die(c, Rect.fromLTWH(u * 8 + k * (dw + u * 0.2), h / 2 - dw / 2, dw, dw), dice[k], false);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]) {
    final u = _u(size);
    final col = (p.dx / u).floor();
    final top = p.dy < size.height / 2;
    final human = info?.human ?? 0;
    if (col == 6) return human == 0 ? TavlaRules.bar0 : TavlaRules.bar1;
    if (col >= 13) return human == 0 ? TavlaRules.off0 : TavlaRules.off1;
    final k = col < 6 ? col : col - 1;
    if (k < 0 || k > 11) return -1;
    return top ? 12 + k : 11 - k;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, pieces[seat], ring: true);
}
