import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_game.dart';
import 'board_view.dart';
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
