import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'pachisi.dart';
import 'skins.dart';
import 'skins_dice.dart';

/// Paçisi tahtası: 19×19 ızgarada haç; kollar 3×8, ortada 3×3 Charkoni.
/// Oyuncu 0 alt, 1 sağ, 2 üst, 3 sol kolda (saat yönünün tersine sıra).
class PachisiSkin extends BoardSkin {
  const PachisiSkin();

  static const _n = 19.0;

  /// Ortak döngü (68 kare), alt kolun ucundan başlayıp saat yönünün tersine.
  static final List<(int, int)> loop = _buildLoop();

  static List<(int, int)> _buildLoop() {
    final out = <(int, int)>[];
    // Alt kol (oyuncu 0) için 17 kare; diğer kollar 90° döndürülerek.
    final arm = <(int, int)>[
      (9, 18), // uç
      for (var y = 18; y >= 11; y--) (10, y), // sağ sütun, merkeze doğru
    ];
    final tail = <(int, int)>[for (var y = 11; y <= 18; y++) (8, y)]; // sol sütun, dışa doğru
    // Kol başına: uç, sağ sütun (8), sonra bir sonraki kolun... Döngüyü kol kol kur:
    // kol a: [uç_a, sağ_a (8)] + [sol_(a+1) değil] — saat yönünün tersine giderken
    // alt kolun sağ sütunundan sağ kolun alt satırına geçilir.
    (int, int) rot((int, int) p, int k) {
      var (x, y) = p;
      for (var i = 0; i < k; i++) {
        // Saat yönünün tersine 90° (ekranda): (x, y) → (y, 18 - x)
        final nx = y, ny = 18 - x;
        x = nx;
        y = ny;
      }
      return (x, y);
    }

    for (var a = 0; a < 4; a++) {
      // Kolun dışa giden sol sütunu, ardından ucu ve merkeze dönen sağ sütunu.
      if (a > 0) out.addAll([for (final p in tail) rot(p, a)]);
      out.addAll([for (final p in arm) rot(p, a)]);
    }
    out.addAll(tail); // alt kolun sol sütunu (döngünün sonu)
    return out;
  }

  /// Oyuncunun özel orta sütunu: m1 (merkeze en yakın) … m7.
  static (int, int) privateSq(int p, int j) {
    var (x, y) = (9, 11 + j);
    for (var i = 0; i < p; i++) {
      final nx = y, ny = 18 - x;
      x = nx;
      y = ny;
    }
    return (x, y);
  }

  /// Bir yolun karesi (prog 0..82) → ızgara.
  static (int, int) square(int p, int prog) {
    final sq = PachisiRules.loopSquare(p, prog);
    if (sq >= 0) return loop[sq];
    final j = prog < 7 ? prog : 82 - prog;
    return privateSq(p, j);
  }

  @override
  double aspect(BoardState s) => 1;

  Offset _c(Size size, double x, double y) {
    final u = size.width / _n;
    return Offset((x + 0.5) * u, (y + 0.5) * u);
  }

  /// Oyuncu köşesi (bekleme alanı): 0 sağ alt, 1 sağ üst, 2 sol üst, 3 sol alt.
  static (double, double) _corner(int p) => const [(15.0, 15.0), (15.0, 3.0), (3.0, 3.0), (3.0, 15.0)][p];

  Offset _piecePos(Size size, GridState s, int idx) {
    final p = idx ~/ 4, k = idx % 4;
    final v = s.cells[idx];
    if (v < 0) {
      final (cx, cy) = _corner(p);
      final dx = cx > 9 ? 1.6 : -1.6, dy = cy > 9 ? 1.6 : -1.6;
      return _c(size, cx + dx + (k % 2 - 0.5) * 1.6, cy + dy + (k ~/ 2 - 0.5) * 1.6);
    }
    if (v == PachisiRules.home) {
      // Charkoni'de, kendi kolu tarafında.
      final base = privateSq(p, 0);
      final toward = (9 + (base.$1 - 9) * 0.55, 9 + (base.$2 - 9) * 0.55);
      final side = (base.$2 == 9) ? (0.0, 1.0) : (1.0, 0.0);
      final off = (k - 1.5) * 0.55;
      return _c(size, toward.$1 + side.$1 * off, toward.$2 + side.$2 * off);
    }
    final (x, y) = square(p, v);
    // Aynı karede birden çok taş: küçük kaydırma.
    var same = 0;
    for (var o = 0; o < idx; o++) {
      final ov = s.cells[o];
      if (ov < 0 || ov == PachisiRules.home) continue;
      if (square(o ~/ 4, ov) == (x, y)) same++;
    }
    final a = same * 1.9;
    final rr = same == 0 ? 0.0 : 0.22;
    return _c(size, x + math.cos(a) * rr, y + math.sin(a) * rr);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final u = size.width / _n;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.5)), Paint()..color = const Color(0xFF3B2A1E));
    final line = Paint()
      ..color = const Color(0xFF5A4030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, u * 0.05);
    Rect cell(int x, int y) => Rect.fromLTWH(x * u, y * u, u, u).deflate(u * 0.03);
    // Kollar: kumaş renginde kareler, orta sütun oyuncunun renginde.
    for (var p = 0; p < 4; p++) {
      for (var j = 0; j < 7; j++) {
        final (x, y) = privateSq(p, j);
        c.drawRect(cell(x, y), Paint()..color = kPlayerColors[p].withValues(alpha: 0.55));
        c.drawRect(cell(x, y), line);
      }
    }
    for (var i = 0; i < loop.length; i++) {
      final (x, y) = loop[i];
      final r = cell(x, y);
      c.drawRect(r, Paint()..color = const Color(0xFFF3E3C3));
      c.drawRect(r, line);
      if (PachisiRules.castle(i)) {
        final cross = Paint()
          ..color = const Color(0xFF8A3B2E)
          ..strokeWidth = math.max(1.5, u * 0.08)
          ..strokeCap = StrokeCap.round;
        final d = r.deflate(u * 0.2);
        c.drawLine(d.topLeft, d.bottomRight, cross);
        c.drawLine(d.topRight, d.bottomLeft, cross);
      }
    }
    // Charkoni
    final center = Rect.fromLTWH(8 * u, 8 * u, 3 * u, 3 * u).deflate(u * 0.03);
    c.drawRect(center, Paint()..color = const Color(0xFFE9C46A));
    c.drawRect(center, line);
    // Köşeler: bekleme alanları; sırası gelenin köşesinde kabuklar.
    for (var p = 0; p < 4; p++) {
      final (cx, cy) = _corner(p);
      final dx = cx > 9 ? 1.6 : -1.6, dy = cy > 9 ? 1.6 : -1.6;
      final yard = Rect.fromCenter(center: _c(size, cx + dx, cy + dy), width: u * 3.6, height: u * 3.6);
      c.drawRRect(RRect.fromRectAndRadius(yard, Radius.circular(u * 0.6)), Paint()..color = kPlayerColors[p].withValues(alpha: 0.25));
      if (s.turn == p) {
        c.drawRRect(
            RRect.fromRectAndRadius(yard.inflate(u * 0.15), Radius.circular(u * 0.7)),
            Paint()
              ..color = kHighlight
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.15);
        _shells(c, _c(size, cx - dx * 0.9, cy - dy * 0.9), u, s);
      }
    }
    // Taşlar
    final n = s.vars[3];
    for (var idx = 0; idx < 16; idx++) {
      if (idx % 4 >= n) continue;
      final o = _piecePos(size, s, idx);
      final p = idx ~/ 4;
      final rad = s.cells[idx] == PachisiRules.home ? u * 0.26 : u * 0.36;
      drawDisc(c, o, rad, kPlayerColors[p], ring: true);
      if (info.colorBlind) drawText(c, '${p + 1}', o, u * 0.32, Colors.white);
      if (s.last == idx) c.drawCircle(o, rad * 0.25, Paint()..color = kHighlight);
      if (info.hintTo == idx) drawHint(c, Rect.fromCircle(center: o, radius: u * 0.5));
    }
    if (info.canAct) {
      final rules = PachisiRules(n);
      for (final m in rules.moves(s)) {
        if (m == kPass) continue;
        final idx = mvTo(m);
        final t = rules.target(s, idx, s.vars[1]);
        if (t == null) continue;
        final o = t == PachisiRules.home ? _c(size, 9, 9) : _c(size, square(idx ~/ 4, t).$1.toDouble(), square(idx ~/ 4, t).$2.toDouble());
        drawTarget(c, o, u * 0.16);
        drawTarget(c, _piecePos(size, s, idx), u * 0.1);
      }
    }
  }

  /// Altı kabuk: ağzı yukarı olanlar açık renkli ve yarıklı; altında değer.
  void _shells(Canvas c, Offset o, double u, GridState s) {
    final v = s.vars[1];
    final up = s.vars[2];
    for (var i = 0; i < 6; i++) {
      final p = o + Offset((i % 3 - 1) * u * 0.75, (i ~/ 3 - 0.75) * u * 0.6);
      final r = Rect.fromCenter(center: p, width: u * 0.62, height: u * 0.42);
      final open = v != 0 && i < up;
      c.drawOval(r.shift(Offset(0, u * 0.04)), Paint()..color = Colors.black.withValues(alpha: 0.25));
      c.drawOval(r, Paint()..color = v == 0 ? const Color(0xFFD8CFC0) : (open ? const Color(0xFFFFF8EC) : const Color(0xFFC9A27C)));
      if (open) {
        c.drawLine(
            p - Offset(u * 0.2, 0),
            p + Offset(u * 0.2, 0),
            Paint()
              ..color = const Color(0xFF6B4A2E)
              ..strokeWidth = u * 0.05
              ..strokeCap = StrokeCap.round);
      }
    }
    if (v != 0) drawText(c, '$v', o + Offset(0, u * 0.95), u * 0.6, Colors.white);
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final u = size.width / _n;
    final rules = PachisiRules(s.vars[3]);
    final movable = <int>{
      if (!rules.needsChance(s) && !rules.isOver(s))
        for (final m in rules.moves(s))
          if (m != kPass) mvTo(m)
    };
    final who = rules.isOver(s) ? s.turn : rules.mover(s);
    int? best;
    var bestD = u * 0.7;
    for (var k = 0; k < s.vars[3]; k++) {
      final idx = who * 4 + k;
      final d = (_piecePos(size, s, idx) - p).distance;
      if (d < bestD || (d < u * 0.7 && movable.contains(idx) && !movable.contains(best))) {
        bestD = d;
        best = idx;
      }
    }
    if (best == null) return -1;
    // Aynı yerdeki taşlardan oynanabilir olanı seç.
    if (!movable.contains(best)) {
      for (final m in movable) {
        if (s.cells[m] == s.cells[best]) return m;
      }
    }
    return best;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawDisc(c, r.center, r.width * 0.45, kPlayerColors[seat]);

  /// Döngü karelerinin ızgarada tek ve haç içinde olduğunu doğrulamak için.
  static bool layoutOk() {
    final all = <(int, int)>{...loop};
    if (all.length != 68) return false;
    for (var p = 0; p < 4; p++) {
      for (var j = 0; j < 7; j++) {
        if (!all.add(privateSq(p, j))) return false;
      }
    }
    for (final (x, y) in all) {
      final inV = x >= 8 && x <= 10, inH = y >= 8 && y <= 10;
      if (!(inV || inH) || (inV && inH)) return false;
    }
    // Ardışık döngü kareleri komşu olmalı (merkez köşelerinde çapraz geçiş).
    for (var i = 0; i < 68; i++) {
      final a = loop[i], b = loop[(i + 1) % 68];
      final dx = (a.$1 - b.$1).abs(), dy = (a.$2 - b.$2).abs();
      if (dx > 1 || dy > 1 || dx + dy == 0) return false;
    }
    return true;
  }
}
