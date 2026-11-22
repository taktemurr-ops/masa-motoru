import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'corner_place.dart';
import 'east_chess.dart';
import 'grid_state.dart';
import 'skins.dart';

const _ink = Color(0xFF4A2E14);

void _glyph(Canvas c, String t, Offset o, double size, Color color, {double angle = 0}) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  c.save();
  c.translate(o.dx, o.dy);
  if (angle != 0) c.rotate(angle);
  tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
  c.restore();
}

void _select(Canvas c, Offset o, double r) => c.drawCircle(
    o,
    r,
    Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, r * 0.12));

/// Çin ve Kore satrancı: 9 × 10 kesişimli tahta, yazılı yuvarlak / sekizgen taşlar.
class XiangqiSkin extends BoardSkin {
  final bool janggi;
  const XiangqiSkin({this.janggi = false});

  static const _namesX = [
    ['', '兵', '炮', '俥', '傌', '相', '仕', '帥'],
    ['', '卒', '砲', '車', '馬', '象', '士', '將'],
  ];
  static const _namesJ = [
    ['', '卒', '包', '車', '馬', '象', '士', '楚'],
    ['', '兵', '包', '車', '馬', '象', '士', '漢'],
  ];
  static const _inkX = [Color(0xFFB3261E), Color(0xFF1F2328)];
  static const _inkJ = [Color(0xFF1E6B4E), Color(0xFFB3261E)];

  @override
  double aspect(BoardState s) => 9 / 10;

  bool _flip(BoardPaintInfo? info) => info?.human == 1;

  Offset pos(Size size, int i, bool flip) {
    if (flip) i = 89 - i;
    final w = size.width / 9, h = size.height / 10;
    return Offset((i % 9 + 0.5) * w, (i ~/ 9 + 0.5) * h);
  }

  static Path octagon(Offset o, double r) {
    final p = Path();
    for (var k = 0; k < 8; k++) {
      final a = math.pi / 8 + k * math.pi / 4;
      final q = o + Offset(math.cos(a), math.sin(a)) * r;
      if (k == 0) {
        p.moveTo(q.dx, q.dy);
      } else {
        p.lineTo(q.dx, q.dy);
      }
    }
    return p..close();
  }

  void drawPiece(Canvas c, Offset o, double r, int v) {
    final col = eColor(v), t = eType(v);
    final ink = (janggi ? _inkJ : _inkX)[col];
    final name = (janggi ? _namesJ : _namesX)[col][t];
    if (janggi) {
      final rr = r * (t == xG ? 1.08 : (t == xS || t == xA ? 0.8 : 0.94));
      final path = octagon(o, rr);
      c.drawPath(path.shift(Offset(0, rr * 0.08)), Paint()..color = Colors.black.withValues(alpha: 0.25));
      c.drawPath(path, Paint()..color = const Color(0xFFF3E6C8));
      c.drawPath(
          path,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, rr * 0.08));
      _glyph(c, name, o, rr * 0.95, ink);
      return;
    }
    c.drawCircle(o + Offset(0, r * 0.08), r, Paint()..color = Colors.black.withValues(alpha: 0.25));
    c.drawCircle(o, r, Paint()..color = const Color(0xFFF3E6C8));
    c.drawCircle(
        o,
        r * 0.84,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r * 0.06));
    _glyph(c, name, o, r * 0.95, ink);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final flip = _flip(info);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)), Paint()..color = const Color(0xFFE3BE7E));
    final line = Paint()
      ..color = _ink
      ..strokeWidth = 1.6;
    Offset p(int col, int row) => pos(size, row * 9 + col, false);
    for (var r = 0; r < 10; r++) {
      c.drawLine(p(0, r), p(8, r), line);
    }
    for (var col = 0; col < 9; col++) {
      if (janggi || col == 0 || col == 8) {
        c.drawLine(p(col, 0), p(col, 9), line);
      } else {
        c.drawLine(p(col, 0), p(col, 4), line);
        c.drawLine(p(col, 5), p(col, 9), line);
      }
    }
    for (final top in const [0, 7]) {
      c.drawLine(p(3, top), p(5, top + 2), line);
      c.drawLine(p(5, top), p(3, top + 2), line);
    }
    if (!janggi) {
      // Nehir: yazı yerine iki ince dalga.
      final a = p(0, 4), b = p(8, 5);
      final wave = Paint()
        ..color = _ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final y in [a.dy + (b.dy - a.dy) * 0.38, a.dy + (b.dy - a.dy) * 0.62]) {
        final path = Path()..moveTo(a.dx + 8, y);
        for (var x = a.dx + 8; x < b.dx - 8; x += 14) {
          path.quadraticBezierTo(x + 3.5, y - 3, x + 7, y);
          path.quadraticBezierTo(x + 10.5, y + 3, x + 14, y);
        }
        c.drawPath(path, wave);
      }
    }
    final rad = math.min(size.width / 9, size.height / 10) * 0.44;
    for (var i = 0; i < 90; i++) {
      final o = pos(size, i, flip);
      final v = s.cells[i];
      if (s.last == i) c.drawCircle(o, rad * 1.12, Paint()..color = kHighlight.withValues(alpha: 0.55));
      if (v >= 0) drawPiece(c, o, rad, v);
      if (info.selected == i) _select(c, o, rad * 1.1);
      if (info.targets.contains(i)) drawTarget(c, o, rad * (v >= 0 ? 0.55 : 0.3));
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, Rect.fromCircle(center: o, radius: rad * 1.15));
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final c = (p.dx / size.width * 9).floor(), r = (p.dy / size.height * 10).floor();
    if (c < 0 || r < 0 || c > 8 || r > 9) return -1;
    final i = r * 9 + c;
    return _flip(info) ? 89 - i : i;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawPiece(c, r.center, r.width * 0.42, seat * 8 + xG);
}

/// Japon satrancı: beşgen taşlar; üstte rakibin, altta oyuncunun eli.
class ShogiSkin extends BoardSkin {
  const ShogiSkin();

  static const _names = ['', '歩', '香', '桂', '銀', '金', '角', '飛', '玉', 'と', '杏', '圭', '全', '馬', '龍'];

  @override
  double aspect(BoardState s) => (s as GridState).cols / (s.cols + 2);

  int _viewer(BoardPaintInfo? info) => info?.human == 1 ? 1 : 0;

  /// Görünen satır/sütun → hücre. Satır 0 üst el, 1..n tahta, n+1 alt el.
  int _cellAt(GridState s, int col, int row, int viewer) {
    final n = s.cols;
    final types = ShogiRules(n).handTypes;
    if (row == 0 || row == n + 1) {
      final owner = row == n + 1 ? viewer : 1 - viewer;
      if (col >= types.length) return -1;
      return n * n + owner * 7 + types[col] - 1;
    }
    var i = (row - 1) * n + col;
    if (viewer == 1) i = n * n - 1 - i;
    return i;
  }

  Rect _rect(Size size, int n, int col, int row) {
    final w = size.width / n, h = size.height / (n + 2);
    return Rect.fromLTWH(col * w, row * h, w, h);
  }

  static void drawPiece(Canvas c, Rect r, int type, bool upsideDown) {
    final o = r.center, w = r.width * 0.84, h = r.height * 0.9;
    c.save();
    c.translate(o.dx, o.dy);
    if (upsideDown) c.rotate(math.pi);
    final path = Path()
      ..moveTo(0, -h / 2)
      ..lineTo(w * 0.36, -h * 0.3)
      ..lineTo(w * 0.46, h / 2)
      ..lineTo(-w * 0.46, h / 2)
      ..lineTo(-w * 0.36, -h * 0.3)
      ..close();
    c.drawPath(path.shift(Offset(0, h * 0.04)), Paint()..color = Colors.black.withValues(alpha: 0.22));
    c.drawPath(path, Paint()..color = const Color(0xFFF2D9A2));
    c.drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, w * 0.04));
    _glyph(c, _names[type], Offset(0, h * 0.06), w * 0.58, type >= 9 ? const Color(0xFFB3261E) : const Color(0xFF1F2328));
    c.restore();
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final n = s.cols;
    final viewer = _viewer(info);
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)), Paint()..color = const Color(0xFF8A6A45));
    final board = Rect.fromPoints(_rect(size, n, 0, 1).topLeft, _rect(size, n, n - 1, n).bottomRight);
    c.drawRect(board, Paint()..color = const Color(0xFFE8C887));
    final line = Paint()
      ..color = _ink
      ..strokeWidth = 1.2;
    for (var k = 0; k <= n; k++) {
      final x = board.left + board.width * k / n, y = board.top + board.height * k / n;
      c.drawLine(Offset(x, board.top), Offset(x, board.bottom), line);
      c.drawLine(Offset(board.left, y), Offset(board.right, y), line);
    }
    if (n == 9) {
      for (final (a, b) in const [(3, 3), (6, 3), (3, 6), (6, 6)]) {
        c.drawCircle(Offset(board.left + board.width * a / 9, board.top + board.height * b / 9), 3, Paint()..color = _ink);
      }
    }
    final types = ShogiRules(n).handTypes;
    for (var row = 0; row < n + 2; row++) {
      for (var col = 0; col < n; col++) {
        final i = _cellAt(s, col, row, viewer);
        if (i < 0) continue;
        final r = _rect(size, n, col, row);
        if (i < n * n) {
          if (s.last == i) c.drawRect(r.deflate(1), Paint()..color = kHighlight.withValues(alpha: 0.45));
          final v = s.cells[i];
          if (v >= 0) drawPiece(c, r, sType(v), sColor(v) != viewer);
        } else {
          final owner = row == n + 1 ? viewer : 1 - viewer;
          final count = s.cells[i];
          final t = types[col];
          c.drawRRect(RRect.fromRectAndRadius(r.deflate(2), const Radius.circular(6)), Paint()..color = Colors.black.withValues(alpha: 0.12));
          if (count > 0) {
            drawPiece(c, r.deflate(r.width * 0.08), t, owner != viewer);
            if (count > 1) {
              final b = r.bottomRight - Offset(r.width * 0.2, r.height * 0.2);
              c.drawCircle(b, r.width * 0.17, Paint()..color = const Color(0xFF1F2328));
              _glyph(c, '$count', b, r.width * 0.22, Colors.white);
            }
          }
        }
        if (info.selected == i) c.drawRect(r.deflate(1), Paint()..color = const Color(0x664CAF50));
        if (info.targets.contains(i)) drawTarget(c, r.center, r.width * (i < n * n && s.cells[i] >= 0 ? 0.45 : 0.16));
        if (info.hintFrom == i || info.hintTo == i) drawHint(c, r);
      }
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final n = s.cols;
    final col = (p.dx / size.width * n).floor(), row = (p.dy / size.height * (n + 2)).floor();
    if (col < 0 || row < 0 || col >= n || row > n + 1) return -1;
    return _cellAt(s, col, row, _viewer(info));
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) => drawPiece(c, r, sK, seat != info.human && info.human >= 0);
}

/// Köşe yerleştirme: üstte tahta, altta oyuncunun taş kutusu, en altta
/// döndür / çevir düğmeleri. Seçili taşın yönelimi burada tutulur.
class CornerSkin extends BoardSkin {
  const CornerSkin();
  static const colors = [Color(0xFF1F9E89), Color(0xFFE4572E)];
  static final List<int> _orient = List.filled(21, 0);
  static int _last = -1;

  static const _cols = 7, _trayRows = 3;
  static const _trayH = 6.0, _btnH = 1.6;

  CornerRules _r(GridState s) => CornerRules(s.cols);

  @override
  double aspect(BoardState s) {
    final n = (s as GridState).cols;
    return n / (n + _trayH + _btnH);
  }

  double _u(Size size, int n) => size.width / n;

  int _viewer(BoardPaintInfo? info) => (info?.human ?? 0) == 1 ? 1 : 0;

  Rect _box(Size size, int n, int k) {
    final u = _u(size, n), bw = n * u / _cols, bh = _trayH * u / _trayRows;
    return Rect.fromLTWH((k % _cols) * bw, n * u + (k ~/ _cols) * bh, bw, bh);
  }

  Rect _button(Size size, int n, int k) {
    final u = _u(size, n);
    final top = (n + _trayH) * u;
    return Rect.fromLTWH(size.width * (k == 0 ? 0.1 : 0.55), top + u * 0.2, size.width * 0.35, (_btnH - 0.4) * u);
  }

  static void _cell(Canvas c, Rect r, Color col) {
    c.drawRRect(RRect.fromRectAndRadius(r.deflate(r.width * 0.04), Radius.circular(r.width * 0.18)), Paint()..color = col);
    c.drawRRect(
        RRect.fromRectAndRadius(r.deflate(r.width * 0.2), Radius.circular(r.width * 0.12)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r.width * 0.08));
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final n = s.cols;
    final rules = _r(s);
    final viewer = _viewer(info);
    final u = _u(size, n);
    final sel = info.selected;
    if (sel != null && sel >= rules.trayBase) {
      final (_, piece, o) = rules.fromTray(sel);
      _last = piece;
      _orient[piece] = o;
    }
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)), Paint()..color = const Color(0xFF23262E));
    final lastCells = s.vars[2] > 0 ? rules.cellsOf(mv(s.vars[2] - 1, s.vars[3] - 1)).toSet() : const <int>{};
    for (var i = 0; i < n * n; i++) {
      final r = Rect.fromLTWH((i % n) * u, (i ~/ n) * u, u, u);
      final v = s.cells[i];
      c.drawRect(r.deflate(0.5), Paint()..color = const Color(0xFF353A45));
      if (v >= 0) {
        _cell(c, r, colors[v]);
        if (lastCells.contains(i)) c.drawRect(r.deflate(u * 0.38), Paint()..color = kHighlight);
      } else {
        for (final p in const [0, 1]) {
          if (i == rules.start(p) && !s.cells.take(n * n).contains(p)) {
            c.drawCircle(r.center, u * 0.28, Paint()..color = colors[p].withValues(alpha: 0.7));
          }
        }
      }
      if (info.targets.contains(i)) drawTarget(c, r.center, u * 0.2);
      if (info.hintTo == i) drawHint(c, r);
    }
    // İpucu: seçili taşın önerilen yerine soluk önizleme.
    final ht = info.hintTo;
    if (sel != null && sel >= rules.trayBase && ht != null && info.targets.contains(ht)) {
      final t = ht;
      for (final i in rules.cellsOf(mv(sel, t))) {
        c.drawRect(Rect.fromLTWH((i % n) * u, (i ~/ n) * u, u, u).deflate(u * 0.08), Paint()..color = colors[viewer].withValues(alpha: 0.35));
      }
    }
    // Taş kutusu.
    for (var k = 0; k < 21; k++) {
      final box = _box(size, n, k);
      final avail = rules.has(s, viewer, k);
      final o = _orient[k];
      final selected = sel != null && sel >= rules.trayBase && rules.fromTray(sel).$2 == k;
      c.drawRRect(RRect.fromRectAndRadius(box.deflate(3), const Radius.circular(8)),
          Paint()..color = selected ? const Color(0x664CAF50) : (k == _last ? const Color(0x22FFFFFF) : const Color(0x11FFFFFF)));
      if (!avail) continue;
      final shape = cornerShape(k, o);
      var w = 0, h = 0;
      for (final (x, y) in shape) {
        if (x > w) w = x;
        if (y > h) h = y;
      }
      final cs = math.min(box.width, box.height) * 0.8 / 5;
      final ox = box.center.dx - (w + 1) * cs / 2, oy = box.center.dy - (h + 1) * cs / 2;
      for (final (x, y) in shape) {
        _cell(c, Rect.fromLTWH(ox + x * cs, oy + y * cs, cs, cs), colors[viewer]);
      }
      final hf = info.hintFrom;
      if (hf != null && hf >= rules.trayBase && rules.fromTray(hf).$2 == k) drawHint(c, box);
    }
    // Rakibin kalan taş sayısı ve düğmeler.
    for (final k in const [0, 1]) {
      final r = _button(size, n, k);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)), Paint()..color = _last >= 0 ? const Color(0xFF3E4452) : const Color(0xFF2B2F38));
      final ic = r.center, rad = r.height * 0.28;
      final pen = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, rad * 0.25)
        ..strokeCap = StrokeCap.round;
      if (k == 0) {
        c.drawArc(Rect.fromCircle(center: ic, radius: rad), -math.pi * 0.4, math.pi * 1.6, false, pen);
        final tip = ic + Offset(math.cos(-math.pi * 0.4), math.sin(-math.pi * 0.4)) * rad;
        c.drawLine(tip, tip + Offset(-rad * 0.5, -rad * 0.15), pen);
        c.drawLine(tip, tip + Offset(-rad * 0.1, rad * 0.5), pen);
      } else {
        c.drawLine(ic + Offset(0, -rad), ic + Offset(0, rad), pen);
        c.drawLine(ic + Offset(-rad * 0.3, -rad * 0.6), ic + Offset(-rad * 1.2, 0), pen);
        c.drawLine(ic + Offset(-rad * 1.2, 0), ic + Offset(-rad * 0.3, rad * 0.6), pen);
        c.drawLine(ic + Offset(rad * 0.3, -rad * 0.6), ic + Offset(rad * 1.2, 0), pen);
        c.drawLine(ic + Offset(rad * 1.2, 0), ic + Offset(rad * 0.3, rad * 0.6), pen);
      }
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as GridState;
    final n = s.cols;
    final rules = _r(s);
    final viewer = _viewer(info);
    final u = _u(size, n);
    if (p.dy < n * u) {
      final c = (p.dx / u).floor(), r = (p.dy / u).floor();
      return c >= 0 && c < n && r >= 0 && r < n ? r * n + c : -1;
    }
    for (var k = 0; k < 21; k++) {
      if (_box(size, n, k).contains(p)) {
        if (!rules.has(s, viewer, k)) return -1;
        _last = k;
        return rules.trayCell(viewer, k, _orient[k]);
      }
    }
    for (final k in const [0, 1]) {
      if (_button(size, n, k).contains(p) && _last >= 0) {
        final o = _orient[_last];
        _orient[_last] = k == 0 ? (o ~/ 4) * 4 + (o + 1) % 4 : (o + 4) % 8;
        return rules.trayCell(viewer, _last, _orient[_last]);
      }
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    final cs = r.width * 0.3;
    for (final (x, y) in const [(0, 0), (1, 0), (1, 1)]) {
      _cell(c, Rect.fromLTWH(r.center.dx - cs + x * cs, r.center.dy - cs + y * cs, cs, cs), colors[seat]);
    }
  }
}
