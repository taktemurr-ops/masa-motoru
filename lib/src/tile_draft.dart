import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'skins.dart';

// ======================================================================
// Çini Döşeme: atölyelerden karo seçip duvar deseni kurma (karo seçme
// mekaniği). Ad, çizim ve puan çizelgesi özgün.
// 5 çini rengi, torbada her renkten 20 karo. Tur başında her atölyeye 4
// karo çekilir. Sıradaki oyuncu bir atölyeden ya da orta tepsiden bir rengin
// hepsini alır (atölyede kalanlar ortaya iner); bunları desen sıralarından
// birine (1..5 karoluk) koyar, sığmayanlar kırık karo şeridine düşer. Ortadan
// ilk alan "ilk el" taşını da alır (şeritte bir kırık sayılır) ve sonraki
// turu başlatır. Bütün karolar alınınca dolu sıralardan birer karo duvara
// geçer: yatay ve dikey komşu zincirleri puan getirir. Kırık şeridi
// −1 −1 −2 −2 −2 −3 −3. Bir oyuncu duvarında bir yatay sırayı
// tamamlayınca oyun o turun sonunda biter. Bitiş armağanları (özgün):
// yatay sıra 2, dikey sıra 5, bir rengin beşi 8.

class CiniState extends BoardState {
  final int players, shops;

  /// Atölyelerdeki karolar: shops*5 renk sayısı; son 5 orta tepsi.
  final List<int> src;
  final List<int> lineColor, lineCount; // players*5
  final List<int> wall; // oyuncu başına 25 bitlik maske
  final List<int> floor; // kırık şeridi (ilk el taşı dâhil)
  final List<int> score;
  final List<int> bag, box;

  /// [0] bitti, [1] dağıtım bekleniyor, [2] ilk el taşı ortada,
  /// [3] sonraki turu açacak oyuncu, [4] tur, [5] bitiş turu.
  final List<int> vars;

  CiniState(this.players, this.shops, this.src, this.lineColor, this.lineCount, this.wall, this.floor, this.score, this.bag, this.box,
      this.vars);

  int at(int source, int color) => src[source * 5 + color];

  @override
  CiniState copy() => copyBase(CiniState(players, shops, List.of(src), List.of(lineColor), List.of(lineCount), List.of(wall),
      List.of(floor), List.of(score), List.of(bag), List.of(box), List.of(vars)));

  @override
  Map<String, Object?> toJson() => {
        ...baseJson(),
        'n': players,
        'f': shops,
        's': src,
        'lc': lineColor,
        'ln': lineCount,
        'w': wall,
        'fl': floor,
        'sc': score,
        'b': bag,
        'x': box,
        'v': vars,
      };

  static CiniState read(Map<String, dynamic> j) {
    final s = CiniState((j['n'] as num).toInt(), (j['f'] as num).toInt(), intList(j['s']), intList(j['lc']), intList(j['ln']),
        intList(j['w']), intList(j['fl']), intList(j['sc']), intList(j['b']), intList(j['x']), intList(j['v']));
    s.readBase(j);
    return s;
  }
}

class TileDraftRules extends BoardRules<CiniState> {
  final int seats;
  const TileDraftRules([this.seats = 2]);

  @override
  String get id => 'tile_draft';

  @override
  int get players => seats;

  @override
  int get maxPly => 600;

  @override
  bool get stochastic => true;

  static const floorPenalty = [1, 1, 2, 2, 2, 3, 3];
  static const lineTarget = 900, floorLine = 5;

  static int shopsFor(int p) => p * 2 + 1;

  /// Duvarda [row] sırasında [color] karosunun sütunu.
  static int wallCol(int row, int color) => (color + row) % 5;
  static int wallColor(int row, int col) => (col - row + 5) % 5;

  @override
  CiniState initial(SeededRandom r) {
    final f = shopsFor(seats);
    return CiniState(seats, f, List.filled((f + 1) * 5, 0), List.filled(seats * 5, -1), List.filled(seats * 5, 0),
        List.filled(seats, 0), List.filled(seats, 0), List.filled(seats, 0), List.filled(5, 20), List.filled(5, 0), [0, 1, 1, 0, 0, 0]);
  }

  @override
  bool needsChance(CiniState s) => s.vars[1] == 1 && s.vars[0] == 0;

  int _draw(CiniState s, SeededRandom r) {
    var total = s.bag.fold(0, (a, b) => a + b);
    if (total == 0) {
      for (var c = 0; c < 5; c++) {
        s.bag[c] += s.box[c];
        s.box[c] = 0;
      }
      total = s.bag.fold(0, (a, b) => a + b);
      if (total == 0) return -1;
    }
    var k = r.nextInt(total);
    for (var c = 0; c < 5; c++) {
      if (k < s.bag[c]) {
        s.bag[c]--;
        return c;
      }
      k -= s.bag[c];
    }
    return -1;
  }

  @override
  void applyChance(CiniState s, SeededRandom r) {
    for (var f = 0; f < s.shops; f++) {
      for (var k = 0; k < 4; k++) {
        final c = _draw(s, r);
        if (c >= 0) s.src[f * 5 + c]++;
      }
    }
    s.vars[1] = 0;
    s.vars[2] = 1;
    if (s.src.every((x) => x == 0)) s.vars[0] = 1; // karo kalmadı
    s.turn = s.vars[3];
    s.vars[4]++;
  }

  bool canPlace(CiniState s, int p, int row, int color) {
    final i = p * 5 + row;
    if (s.lineCount[i] >= row + 1) return false;
    if (s.lineColor[i] >= 0 && s.lineColor[i] != color) return false;
    return s.wall[p] & (1 << (row * 5 + wallCol(row, color))) == 0;
  }

  @override
  List<int> moves(CiniState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final out = <int>[];
    for (var src = 0; src <= s.shops; src++) {
      for (var c = 0; c < 5; c++) {
        if (s.at(src, c) == 0) continue;
        for (var row = 0; row < 5; row++) {
          if (canPlace(s, s.turn, row, c)) out.add(mv(src * 5 + c, lineTarget + row));
        }
        out.add(mv(src * 5 + c, lineTarget + floorLine));
      }
    }
    return out;
  }

  void _toFloor(CiniState s, int p, int color, int count) {
    for (var k = 0; k < count; k++) {
      if (s.floor[p] < 7) {
        s.floor[p]++;
      }
      if (color >= 0) s.box[color]++;
    }
  }

  @override
  void apply(CiniState s, int m) {
    final p = s.turn;
    final from = mvFrom(m), row = mvTo(m) - lineTarget;
    final src = from ~/ 5, color = from % 5;
    final count = s.at(src, color);
    s.src[from] = 0;
    if (src < s.shops) {
      for (var c = 0; c < 5; c++) {
        s.src[s.shops * 5 + c] += s.src[src * 5 + c];
        s.src[src * 5 + c] = 0;
      }
    } else if (s.vars[2] == 1) {
      s.vars[2] = 0;
      s.vars[3] = p;
      _toFloor(s, p, -1, 1);
    }
    if (row == floorLine) {
      _toFloor(s, p, color, count);
    } else {
      final i = p * 5 + row;
      final room = row + 1 - s.lineCount[i];
      final put = math.min(room, count);
      s.lineColor[i] = color;
      s.lineCount[i] += put;
      _toFloor(s, p, color, count - put);
    }
    s.last = m;
    s.ply++;
    s.turn = (p + 1) % s.players;
    if (s.src.every((x) => x == 0)) _endRound(s);
  }

  /// Duvara yerleştirilen karonun puanı (yatay ve dikey zincirler).
  static int placeScore(int wall, int row, int col) {
    bool has(int r, int c) => r >= 0 && c >= 0 && r < 5 && c < 5 && wall & (1 << (r * 5 + c)) != 0;
    var h = 1, v = 1;
    for (var c = col - 1; has(row, c); c--) {
      h++;
    }
    for (var c = col + 1; has(row, c); c++) {
      h++;
    }
    for (var r = row - 1; has(r, col); r--) {
      v++;
    }
    for (var r = row + 1; has(r, col); r++) {
      v++;
    }
    if (h == 1 && v == 1) return 1;
    return (h > 1 ? h : 0) + (v > 1 ? v : 0);
  }

  void _endRound(CiniState s) {
    var finished = false;
    for (var p = 0; p < s.players; p++) {
      for (var row = 0; row < 5; row++) {
        final i = p * 5 + row;
        if (s.lineCount[i] == row + 1) {
          final color = s.lineColor[i];
          final col = wallCol(row, color);
          s.wall[p] |= 1 << (row * 5 + col);
          s.score[p] += placeScore(s.wall[p], row, col);
          s.box[color] += row;
          s.lineColor[i] = -1;
          s.lineCount[i] = 0;
        }
      }
      var pen = 0;
      for (var k = 0; k < s.floor[p]; k++) {
        pen += floorPenalty[k];
      }
      s.score[p] = math.max(0, s.score[p] - pen);
      s.floor[p] = 0;
      if (rowsDone(s.wall[p]) > 0) finished = true;
    }
    if (finished || s.vars[4] >= 12) {
      for (var p = 0; p < s.players; p++) {
        s.score[p] += bonus(s.wall[p]);
      }
      s.vars[0] = 1;
      s.vars[5] = s.vars[4];
    } else {
      s.vars[1] = 1;
    }
  }

  static int rowsDone(int wall) {
    var n = 0;
    for (var r = 0; r < 5; r++) {
      if ((wall >> (r * 5)) & 31 == 31) n++;
    }
    return n;
  }

  static int bonus(int wall) {
    var b = rowsDone(wall) * 2;
    for (var c = 0; c < 5; c++) {
      var full = true;
      for (var r = 0; r < 5; r++) {
        if (wall & (1 << (r * 5 + c)) == 0) full = false;
      }
      if (full) b += 5;
    }
    for (var color = 0; color < 5; color++) {
      var full = true;
      for (var r = 0; r < 5; r++) {
        if (wall & (1 << (r * 5 + wallCol(r, color))) == 0) full = false;
      }
      if (full) b += 8;
    }
    return b;
  }

  @override
  bool isOver(CiniState s) => s.vars[0] == 1;

  @override
  int winner(CiniState s) {
    if (!isOver(s)) return -1;
    var best = -1, bestV = -1, tie = false;
    for (var p = 0; p < s.players; p++) {
      final v = s.score[p] * 10 + rowsDone(s.wall[p]);
      if (v > bestV) {
        bestV = v;
        best = p;
        tie = false;
      } else if (v == bestV) {
        tie = true;
      }
    }
    return tie ? -1 : best;
  }

  /// Oyuncunun beklenen puanı: mevcut puan + dolu sıraların getirisi −
  /// kırık şeridi + yarım sıraların küçük payı.
  double potential(CiniState s, int p) {
    var v = s.score[p].toDouble();
    var wall = s.wall[p];
    for (var row = 0; row < 5; row++) {
      final i = p * 5 + row;
      if (s.lineCount[i] == 0) continue;
      final col = wallCol(row, s.lineColor[i]);
      if (s.lineCount[i] == row + 1) {
        wall |= 1 << (row * 5 + col);
        v += placeScore(wall, row, col);
      } else {
        v += s.lineCount[i] / (row + 1) * 1.6 - (row + 1 - s.lineCount[i]) * 0.15;
      }
    }
    var pen = 0;
    for (var k = 0; k < s.floor[p]; k++) {
      pen += floorPenalty[k];
    }
    return v - pen + bonus(wall) * 0.5 + rowsDone(wall) * 0.5;
  }

  @override
  double evaluate(CiniState s, int player) {
    final me = potential(s, player);
    var other = 0.0;
    for (var p = 0; p < s.players; p++) {
      if (p != player) other = math.max(other, potential(s, p));
    }
    return (me - other).clamp(-95, 95).toDouble();
  }

  @override
  int? policy(CiniState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.isEmpty) return kPass;
    final p = s.turn;
    final base = potential(s, p);
    var best = ms.first;
    var bestV = -double.infinity;
    for (final m in ms) {
      final c = s.copy();
      // Tur sonunu tetiklemeden etkisini ölç.
      final from = mvFrom(m);
      final count = c.src[from];
      final row = mvTo(m) - lineTarget;
      var v = 0.0;
      if (from ~/ 5 == s.shops && s.vars[2] == 1) v -= 0.6; // ilk el taşı: ceza ama sonraki turu açar
      if (row == floorLine) {
        v -= count * 1.8;
      } else {
        final i = p * 5 + row;
        final room = row + 1 - c.lineCount[i];
        final put = math.min(room, count);
        final over = count - put;
        c.lineColor[i] = from % 5;
        c.lineCount[i] += put;
        c.floor[p] = math.min(7, c.floor[p] + over);
        v += potential(c, p) - base;
        if (put == room) v += 0.8; // sırayı tamamlamak
        v -= over * 0.3;
      }
      v += r.nextDouble() * (0.2 + noise * 5);
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (noise >= 0.6 && r.nextDouble() < (noise - 0.5) * 0.4) return ms[r.nextInt(ms.length)];
    return best;
  }

  @override
  String status(CiniState s, String lang) => [for (var p = 0; p < s.players; p++) '${p + 1}: ${s.score[p]}'].join('  ·  ');

  @override
  CiniState fromJson(Map<String, dynamic> j) => CiniState.read(j);
}

/// Çini Döşeme çizimi: üstte atölye tabakları ve orta tepsi, ortada
/// rakiplerin küçük duvarları, altta ekrana bakan oyuncunun desen sıraları,
/// duvarı ve kırık şeridi.
class TileDraftSkin extends BoardSkin {
  const TileDraftSkin();

  static const colors = [Color(0xFF1F4E9C), Color(0xFF2BA6A0), Color(0xFFD2473A), Color(0xFF2E8B57), Color(0xFFE0A526)];
  static const _bg = Color(0xFFF3E9D6);

  @override
  double aspect(BoardState s) => 12 / 16.8;

  int _main(CiniState s, BoardPaintInfo? info) => info == null || info.viewer < 0 || info.viewer >= s.players ? s.turn : info.viewer;

  /// Çini karosu: renk zemin, beyaz göbek motifi (renk körleri için renge
  /// özgü şekil).
  static void drawTile(Canvas c, Rect r, int color, {bool ghost = false, bool mark = true}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.16));
    if (ghost) {
      c.drawRRect(rr, Paint()..color = colors[color].withValues(alpha: 0.18));
      c.drawRRect(
          rr,
          Paint()
            ..color = colors[color].withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      return;
    }
    c.drawRRect(rr.shift(Offset(0, r.width * 0.06)), Paint()..color = Colors.black.withValues(alpha: 0.25));
    c.drawRRect(rr, Paint()..color = colors[color]);
    if (!mark) return;
    final o = r.center, u = r.width;
    final w = Paint()..color = Colors.white.withValues(alpha: 0.85);
    switch (color) {
      case 0: // lale
        c.drawPath(
            Path()
              ..moveTo(o.dx, o.dy + u * 0.26)
              ..quadraticBezierTo(o.dx - u * 0.3, o.dy - u * 0.05, o.dx - u * 0.14, o.dy - u * 0.26)
              ..lineTo(o.dx, o.dy - u * 0.1)
              ..lineTo(o.dx + u * 0.14, o.dy - u * 0.26)
              ..quadraticBezierTo(o.dx + u * 0.3, o.dy - u * 0.05, o.dx, o.dy + u * 0.26),
            w);
      case 1: // yıldız
        final p = Path();
        for (var k = 0; k < 16; k++) {
          final a = k * math.pi / 8 - math.pi / 2;
          final rad = k.isEven ? u * 0.3 : u * 0.14;
          final pt = o + Offset(math.cos(a), math.sin(a)) * rad;
          if (k == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        c.drawPath(p..close(), w);
      case 2: // nar çiçeği: dört yaprak
        for (var k = 0; k < 4; k++) {
          final a = k * math.pi / 2;
          c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * u * 0.14, u * 0.11, w);
        }
      case 3: // yaprak
        c.drawPath(
            Path()
              ..moveTo(o.dx - u * 0.26, o.dy + u * 0.2)
              ..quadraticBezierTo(o.dx - u * 0.2, o.dy - u * 0.28, o.dx + u * 0.26, o.dy - u * 0.2)
              ..quadraticBezierTo(o.dx + u * 0.2, o.dy + u * 0.26, o.dx - u * 0.26, o.dy + u * 0.2),
            w);
      default: // baklava
        c.drawPath(
            Path()
              ..moveTo(o.dx, o.dy - u * 0.28)
              ..lineTo(o.dx + u * 0.24, o.dy)
              ..lineTo(o.dx, o.dy + u * 0.28)
              ..lineTo(o.dx - u * 0.24, o.dy)
              ..close(),
            w);
    }
  }

  // ---- yerleşim ----
  static const _cols = 5;

  Offset _shopCenter(Size size, CiniState s, int f) {
    final u = size.width / 12;
    final row = f ~/ _cols, col = f % _cols;
    final inRow = row == 0 ? math.min(_cols, s.shops) : s.shops - _cols;
    final span = 12 / math.max(inRow, 1);
    return Offset((col + 0.5) * span * u, (1.2 + row * 2.4) * u);
  }

  Rect _shopTile(Size size, CiniState s, int f, int k) {
    final u = size.width / 12;
    final o = _shopCenter(size, s, f);
    return Rect.fromCenter(center: o + Offset((k % 2 - 0.5) * 0.82 * u, (k ~/ 2 - 0.5) * 0.82 * u), width: 0.74 * u, height: 0.74 * u);
  }

  /// Orta tepsi: tek satırda renk yığınları.
  Rect _centerRect(Size size, CiniState s) {
    final u = size.width / 12;
    return Rect.fromLTWH(0.3 * u, 4.9 * u, 11.4 * u, 1.7 * u);
  }

  Rect _centerSlot(Size size, CiniState s, int color) {
    final r = _centerRect(size, s);
    final w = r.width / 6;
    return Rect.fromCenter(center: Offset(r.left + (color + 0.5) * w, r.center.dy), width: math.min(w * 0.8, r.height * 0.55), height: math.min(w * 0.8, r.height * 0.55));
  }

  double _boardTop(Size size) => size.width / 12 * 9.6;

  Rect _lineSlot(Size size, int row, int k) {
    final u = size.width / 12;
    final top = _boardTop(size);
    // Desen sırası sağa yaslı: k=0 duvara en yakın.
    return Rect.fromLTWH((5.6 - (k + 1) * 1.04) * u, top + row * 1.04 * u, 0.96 * u, 0.96 * u);
  }

  Rect _wallSlot(Size size, int row, int col) {
    final u = size.width / 12;
    return Rect.fromLTWH((6.2 + col * 1.04) * u, _boardTop(size) + row * 1.04 * u, 0.96 * u, 0.96 * u);
  }

  Rect _floorSlot(Size size, int k) {
    final u = size.width / 12;
    return Rect.fromLTWH((0.5 + k * 1.1) * u, _boardTop(size) + 5.5 * u, 1.0 * u, 1.0 * u);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as CiniState;
    final u = size.width / 12;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..color = _bg);
    final sel = info.selected;
    // Atölyeler.
    for (var f = 0; f < s.shops; f++) {
      final o = _shopCenter(size, s, f);
      c.drawCircle(o, 1.08 * u, Paint()..color = const Color(0xFFE2D3B5));
      c.drawCircle(
          o,
          1.08 * u,
          Paint()
            ..color = const Color(0xFF9C7A4A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      var k = 0;
      for (var color = 0; color < 5; color++) {
        for (var t = 0; t < s.at(f, color); t++) {
          final r = _shopTile(size, s, f, k++);
          drawTile(c, r, color, mark: true);
          if (sel == f * 5 + color) {
            c.drawRRect(
                RRect.fromRectAndRadius(r.inflate(2), Radius.circular(r.width * 0.2)),
                Paint()
                  ..color = const Color(0xFF4CAF50)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3);
          }
          if (info.hintFrom == f * 5 + color) drawHint(c, r.inflate(2));
        }
      }
    }
    // Orta tepsi.
    final cr = _centerRect(size, s);
    c.drawRRect(RRect.fromRectAndRadius(cr, Radius.circular(u * 0.5)), Paint()..color = const Color(0xFFE9DCC2));
    for (var color = 0; color < 5; color++) {
      final n = s.at(s.shops, color);
      final r = _centerSlot(size, s, color);
      if (n == 0) {
        drawTile(c, r, color, ghost: true);
        continue;
      }
      drawTile(c, r, color);
      _label(c, '×$n', Offset(r.center.dx, r.bottom + u * 0.28), u * 0.42, const Color(0xFF3B2F22));
      final code = s.shops * 5 + color;
      if (sel == code) {
        c.drawRRect(
            RRect.fromRectAndRadius(r.inflate(3), Radius.circular(r.width * 0.2)),
            Paint()
              ..color = const Color(0xFF4CAF50)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
      if (info.hintFrom == code) drawHint(c, r.inflate(3));
    }
    if (s.vars[2] == 1) {
      // İlk el taşı.
      final w = cr.width / 6;
      final o = Offset(cr.left + 5.5 * w, cr.center.dy);
      c.drawCircle(o, u * 0.42, Paint()..color = const Color(0xFF3B2F22));
      _label(c, '1', o, u * 0.5, Colors.white);
    }
    // Rakiplerin küçük duvarları.
    final me = _main(s, info);
    final others = [for (var p = 0; p < s.players; p++) if (p != me) p];
    final ow = 12 / math.max(others.length, 1);
    for (var k = 0; k < others.length; k++) {
      final p = others[k];
      final left = (k * ow + ow / 2 - 1.6) * u;
      final oTop = 6.9 * u;
      final cell = 0.42 * u;
      for (var row = 0; row < 5; row++) {
        for (var col = 0; col < 5; col++) {
          final r = Rect.fromLTWH(left + col * cell, oTop + row * cell, cell * 0.92, cell * 0.92);
          final filled = s.wall[p] & (1 << (row * 5 + col)) != 0;
          drawTile(c, r, TileDraftRules.wallColor(row, col), ghost: !filled, mark: false);
        }
      }
      _label(c, '${p + 1}', Offset(left + 2.75 * u, oTop + 0.5 * u), u * 0.5, s.turn == p ? const Color(0xFFB5462F) : const Color(0xFF3B2F22));
      _label(c, '${s.score[p]}', Offset(left + 2.75 * u, oTop + 1.4 * u), u * 0.42, const Color(0xFF3B2F22));
    }
    // Ana oyuncu.
    final top = _boardTop(size);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.2 * u, top - 0.3 * u, 11.6 * u, 7.3 * u), Radius.circular(u * 0.4)),
        Paint()..color = const Color(0xFFFFFBF2));
    for (var row = 0; row < 5; row++) {
      final i = me * 5 + row;
      for (var k = 0; k <= row; k++) {
        final r = _lineSlot(size, row, k);
        if (k < s.lineCount[i]) {
          drawTile(c, r, s.lineColor[i]);
        } else {
          c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.16)), Paint()..color = const Color(0xFFE6DAC3));
        }
      }
      final rowRect = Rect.fromLTRB(_lineSlot(size, row, row).left, _lineSlot(size, row, 0).top, _lineSlot(size, row, 0).right,
          _lineSlot(size, row, 0).bottom);
      if (info.targets.contains(TileDraftRules.lineTarget + row)) {
        c.drawRRect(
            RRect.fromRectAndRadius(rowRect.inflate(2), Radius.circular(u * 0.2)),
            Paint()
              ..color = kHighlight
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
      if (info.hintTo == TileDraftRules.lineTarget + row && info.hintFrom != null) drawHint(c, rowRect.inflate(3));
      for (var col = 0; col < 5; col++) {
        final filled = s.wall[me] & (1 << (row * 5 + col)) != 0;
        drawTile(c, _wallSlot(size, row, col), TileDraftRules.wallColor(row, col), ghost: !filled);
      }
    }
    for (var k = 0; k < 7; k++) {
      final r = _floorSlot(size, k);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.16)), Paint()..color = const Color(0xFFEBD3CB));
      if (k < s.floor[me]) {
        c.drawRRect(RRect.fromRectAndRadius(r.deflate(r.width * 0.08), Radius.circular(r.width * 0.14)), Paint()..color = const Color(0xFF8E6E5E));
        final crack = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..strokeWidth = 1.5;
        c.drawLine(r.topLeft + Offset(r.width * 0.3, r.width * 0.2), r.center, crack);
        c.drawLine(r.center, r.bottomRight - Offset(r.width * 0.25, r.width * 0.3), crack);
      }
      _label(c, '−${TileDraftRules.floorPenalty[k]}', Offset(r.center.dx, r.top - u * 0.22), u * 0.3, const Color(0xFF8E3B2E));
    }
    final floorRect = Rect.fromLTRB(_floorSlot(size, 0).left, _floorSlot(size, 0).top, _floorSlot(size, 6).right, _floorSlot(size, 0).bottom);
    if (info.targets.contains(TileDraftRules.lineTarget + TileDraftRules.floorLine)) {
      c.drawRRect(
          RRect.fromRectAndRadius(floorRect.inflate(2), Radius.circular(u * 0.2)),
          Paint()
            ..color = kHighlight
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    _label(c, '${s.score[me]}', Offset(10.6 * u, _floorSlot(size, 0).center.dy), u * 0.8, const Color(0xFF1F4E9C));
  }

  void _label(Canvas c, String t, Offset o, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as CiniState;
    final u = size.width / 12;
    for (var f = 0; f < s.shops; f++) {
      final o = _shopCenter(size, s, f);
      if ((p - o).distance > 1.1 * u) continue;
      var k = 0;
      for (var color = 0; color < 5; color++) {
        for (var t = 0; t < s.at(f, color); t++) {
          if (_shopTile(size, s, f, k++).inflate(2).contains(p)) return f * 5 + color;
        }
      }
      return -1;
    }
    for (var color = 0; color < 5; color++) {
      if (s.at(s.shops, color) > 0 && _centerSlot(size, s, color).inflate(u * 0.2).contains(p)) return s.shops * 5 + color;
    }
    for (var row = 0; row < 5; row++) {
      final y0 = _lineSlot(size, row, 0).top, y1 = _lineSlot(size, row, 0).bottom;
      if (p.dy >= y0 && p.dy <= y1 && p.dx <= _wallSlot(size, row, 4).right) return TileDraftRules.lineTarget + row;
    }
    final fl = _floorSlot(size, 0);
    if (p.dy >= fl.top - u * 0.4 && p.dy <= fl.bottom + u * 0.3) return TileDraftRules.lineTarget + TileDraftRules.floorLine;
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawTile(c, r.deflate(r.width * 0.1), seat % 5);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.3, seat % 2);
  }
}
