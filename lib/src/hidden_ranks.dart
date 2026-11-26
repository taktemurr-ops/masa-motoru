import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'grid_state.dart';
import 'skins.dart';

// ======================================================================
// Gizli Rütbeler: rütbesi rakipten gizli taşlarla yuva avı. Mekanik 1909
// tarihli kamu malı L'Attaque ailesinden; taşlar hayvan temalı, dizilim ve
// taş takımı özgün.
// 8×8 tahta, ortada iki göl (geçilmez). Her taraf 16 taş:
//   Yuva (0) ×1, Fare (1) ×1, Tavşan (2) ×3, Köstebek (3) ×2,
//   Porsuk 4, Tilki 5, Kurt 6, Ayı 7, Kaplan 8, Aslan 9, Fil 10 (birer),
//   Kapan (11) ×2.
// Taş bir kare dik yürür; Tavşan boş kareler boyunca istediği kadar gider.
// Yuva ve Kapan yürümez. Saldırıda büyük rütbe kazanır, eşitler birlikte
// düşer; Fare saldırırken Fil'i yener; Kapan'a saldıran düşer, yalnız
// Köstebek kapanı söker. Rakibin Yuvasını alan ya da rakibi kıpırdayamaz
// bırakan kazanır. Çarpışan taşların rütbesi açılır.
// Hücre: -1 boş, -2 göl; taş = sahip*64 + açık*32 + yürüdü*16 + rütbe.
// vars: [0] bitti, [1] alımsız hamle, [2] kazanan + 1.

class HiddenRanksRules extends BoardRules<GridState> {
  const HiddenRanksRules();

  @override
  String get id => 'hidden_ranks';

  @override
  int get maxPly => 400;

  /// Gizli bilgi: sonuç rakibin dizilişine bağlı; doğrulama kurulumla yetinir.
  @override
  bool get stochastic => true;

  static const n = 8;
  static const flag = 0, spy = 1, scout = 2, miner = 3, top = 10, trap = 11;

  /// Bir tarafın taş takımı.
  static const army = [0, 1, 2, 2, 2, 3, 3, 4, 5, 6, 7, 8, 9, 10, 11, 11];

  static const lakes = {26, 34, 29, 37}; // (2,3) (2,4) (5,3) (5,4)

  static int owner(int v) => v >> 6;
  static int rank(int v) => v & 15;
  static bool revealed(int v) => v & 32 != 0;
  static bool moved(int v) => v & 16 != 0;
  static bool isPiece(int v) => v >= 0;

  static int piece(int owner, int rank) => owner * 64 + rank;

  /// Tohuma bağlı diziliş: Yuva arka sırada, Kapanlar onu korur.
  static List<int> deploy(SeededRandom r) {
    final slots = List.filled(16, -1); // 0..7 ön sıra, 8..15 arka sıra
    final f = 8 + r.nextInt(8);
    slots[f] = flag;
    final guard = <int>[f - 8, if (f > 8) f - 1, if (f < 15) f + 1]..shuffle(math.Random(r.nextInt(1 << 30)));
    var traps = 0;
    for (final g in guard) {
      if (traps < 2 && r.nextDouble() < 0.8) {
        slots[g] = trap;
        traps++;
      }
    }
    final rest = <int>[for (final x in army) x]..remove(flag);
    for (var t = 0; t < traps; t++) {
      rest.remove(trap);
    }
    // Kalan kapanlar arka sıraya, diğerleri karışık.
    final free = [for (var i = 0; i < 16; i++) if (slots[i] < 0) i];
    for (var i = free.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = free[i];
      free[i] = free[j];
      free[j] = t;
    }
    // Kapanlar ve büyükler arkaya eğilimli; tavşanlar öne.
    rest.sort((a, b) => _depth(b).compareTo(_depth(a)));
    final back = free.where((i) => i >= 8).toList(), front = free.where((i) => i < 8).toList();
    for (final rk in rest) {
      final wantBack = _depth(rk) > 0 && back.isNotEmpty;
      final list = wantBack || front.isEmpty ? back : front;
      slots[list.removeAt(0)] = rk;
    }
    return slots;
  }

  static int _depth(int rk) => rk == trap ? 2 : (rk == 2 || rk == 4 || rk == 5 ? -1 : (rk >= 9 ? 1 : 0));

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(n * n, -1);
    for (final l in lakes) {
      cells[l] = -2;
    }
    for (final p in const [0, 1]) {
      final slots = deploy(rnd);
      for (var k = 0; k < 16; k++) {
        final front = k < 8;
        final col = k % 8;
        // Koltuk 0 alt sıralarda (ön sıra 6), koltuk 1 üstte (ön sıra 1).
        final row = p == 0 ? (front ? 6 : 7) : (front ? 1 : 0);
        final c = p == 0 ? col : n - 1 - col;
        cells[row * n + c] = piece(p, slots[k]);
      }
    }
    return GridState(n, n, cells);
  }

  static const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];

  List<int> _gen(GridState s, int p) {
    final out = <int>[];
    for (var i = 0; i < n * n; i++) {
      final v = s.cells[i];
      if (v < 0 || owner(v) != p) continue;
      final rk = rank(v);
      if (rk == flag || rk == trap) continue;
      for (final (dc, dr) in _dirs) {
        var c = i % n + dc, r = i ~/ n + dr;
        while (c >= 0 && r >= 0 && c < n && r < n) {
          final t = s.cells[r * n + c];
          if (t == -2) break;
          if (t >= 0) {
            if (owner(t) != p) out.add(mv(i, r * n + c));
            break;
          }
          out.add(mv(i, r * n + c));
          if (rk != scout) break;
          c += dc;
          r += dr;
        }
      }
    }
    return out;
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : _gen(s, s.turn);

  /// Saldırı sonucu: 1 saldıran kazanır, 0 ikisi düşer, -1 saldıran düşer,
  /// 2 Yuva alındı.
  static int battle(int ra, int rd) {
    if (rd == flag) return 2;
    if (rd == trap) return ra == miner ? 1 : -1;
    if (ra == spy && rd == top) return 1;
    if (ra == rd) return 0;
    return ra > rd ? 1 : -1;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final f = mvFrom(m), t = mvTo(m);
    final a = s.cells[f] | 16;
    final d = s.cells[t];
    s.cells[f] = -1;
    var fight = false;
    if (d < 0) {
      // Tavşan uzun yürüyüşte kendini belli eder.
      final far = (t % n - f % n).abs() + (t ~/ n - f ~/ n).abs() > 1;
      s.cells[t] = far ? a | 32 : a;
    } else {
      fight = true;
      switch (battle(rank(a), rank(d))) {
        case 2:
          s.cells[t] = a | 32;
          s.vars[0] = 1;
          s.vars[2] = p + 1;
        case 1:
          s.cells[t] = a | 32;
        case 0:
          s.cells[t] = -1;
        default:
          s.cells[t] = d | 32;
      }
    }
    s.last = t;
    s.ply++;
    s.vars[1] = fight ? 0 : s.vars[1] + 1;
    s.turn = 1 - p;
    if (s.vars[0] == 1) return;
    if (_gen(s, s.turn).isEmpty) {
      s.vars[0] = 1;
      s.vars[2] = p + 1;
    } else if (s.vars[1] >= 120) {
      s.vars[0] = 1;
      s.vars[2] = 0;
    }
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) => isOver(s) ? s.vars[2] - 1 : -1;

  static const _value = <double>[100, 4, 2, 4, 3, 4, 5, 6, 7, 8.5, 10, 3];
  static double value(int rk) => _value[rk];

  /// Herkesin bildiği malzeme: canlı taşların toplam değeri.
  @override
  double evaluate(GridState s, int player) {
    if (isOver(s)) {
      final w = winner(s);
      return w < 0 ? 0 : (w == player ? 99 : -99);
    }
    var v = 0.0;
    for (final x in s.cells) {
      if (x < 0) continue;
      final val = rank(x) == flag ? 0.0 : value(rank(x));
      v += owner(x) == player ? val : -val;
    }
    return v.clamp(-95, 95).toDouble();
  }

  /// Rakibin gizli taşları için ortak bilgi: açılmamış taşların rütbe
  /// havuzu (takım bilinir, düşen ve açılan taşlar herkesçe görülür).
  static List<int> hiddenPool(GridState s, int enemy) => [
        for (final x in s.cells)
          if (x >= 0 && owner(x) == enemy && !revealed(x)) rank(x)
      ];

  /// Bilinmeyen bir taşın olası rütbeleri (yürüdüyse Yuva/Kapan olamaz).
  static List<int> candidates(List<int> pool, int v) =>
      moved(v) ? [for (final r in pool) if (r != flag && r != trap) r] : pool;

  /// [p] açısından saldırının beklenen değeri (yalnız açık bilgi kullanılır).
  static double attackValue(GridState s, int p, int a, int d) {
    final ra = rank(a);
    double outcome(int rd) => switch (battle(ra, rd)) {
          2 => 500.0,
          1 => value(rd),
          0 => value(rd) - value(ra),
          _ => -value(ra),
        };
    if (revealed(d)) return outcome(rank(d));
    final c = candidates(hiddenPool(s, 1 - p), d);
    if (c.isEmpty) return 0;
    var sum = 0.0;
    for (final rd in c) {
      sum += outcome(rd);
    }
    // Saldırı bilgi de kazandırır.
    return sum / c.length + (ra == scout ? 1.6 : 0.4);
  }

  /// Bilgisayar rakibi: rakibin gizli rütbelerine bakmadan, yalnızca
  /// açılmış taşlar ve ortak havuzla karar verir.
  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final p = s.turn;
    final ms = _gen(s, p);
    if (ms.isEmpty) return kPass;
    final pool = hiddenPool(s, 1 - p);
    double danger(int at, int rk, int skip) {
      // Komşu bilinen daha güçlü rakip taş varsa risk.
      var worst = 0.0;
      for (final (dc, dr) in _dirs) {
        final c = at % n + dc, rr = at ~/ n + dr;
        if (c < 0 || rr < 0 || c >= n || rr >= n) continue;
        final j = rr * n + c;
        if (j == skip) continue;
        final x = s.cells[j];
        if (x < 0 || owner(x) == p) continue;
        if (revealed(x)) {
          final b = battle(rank(x), rk);
          if (b == 1 || b == 2) worst = math.max(worst, value(rk));
        } else if (moved(x) && rk >= 7) {
          // Gizli büyük taş: belirsiz tehdit.
          final cand = candidates(pool, x);
          final stronger = cand.where((q) => q > rk).length;
          if (cand.isNotEmpty) worst = math.max(worst, value(rk) * stronger / cand.length * 0.5);
        }
      }
      return worst;
    }

    var best = ms.first;
    var bestV = -double.infinity;
    for (final m in ms) {
      final f = mvFrom(m), t = mvTo(m);
      final a = s.cells[f];
      final rk = rank(a);
      final d = s.cells[t];
      double v;
      if (d >= 0) {
        v = attackValue(s, p, a, d) * 1.4;
      } else {
        final adv = p == 0 ? (f ~/ n - t ~/ n) : (t ~/ n - f ~/ n);
        v = adv * (rk == scout ? 0.25 : 0.55) - danger(t, rk, f) + danger(f, rk, -1) * 0.8;
        // Yuva çevresinde kalmak (son sıra koruması) ve gereksiz geri adım.
        if (rk >= 9 && adv < 0) v -= 0.4;
        // Uzun tavşan koşusu gizliliği bozar.
        if (rk == scout && ((t % n - f % n).abs() + (t ~/ n - f ~/ n).abs()) > 1) v -= 0.6;
        // Bilinen zayıf rakibe yaklaş.
        for (final (dc, dr) in _dirs) {
          final c = t % n + dc, rr = t ~/ n + dr;
          if (c < 0 || rr < 0 || c >= n || rr >= n) continue;
          final x = s.cells[rr * n + c];
          if (x >= 0 && owner(x) != p && revealed(x) && battle(rk, rank(x)) == 1) v += value(rank(x)) * 0.35;
        }
      }
      v += r.nextDouble() * (0.3 + noise * 6);
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (noise >= 0.5 && r.nextDouble() < (noise - 0.4) * 0.5) return ms[r.nextInt(ms.length)];
    return best;
  }

  @override
  String status(GridState s, String lang) {
    var a = 0, b = 0;
    for (final x in s.cells) {
      if (x < 0) continue;
      if (owner(x) == 0) {
        a++;
      } else {
        b++;
      }
    }
    return '● $a · $b';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

/// Gizli Rütbeler tahtası: çimen kareler, mavi göller; taşlar ayakta duran
/// ahşap levhalar. Ekrana bakan oyuncunun taşları ve açılmış taşlar
/// rütbesiyle, diğerleri arkası dönük çizilir. İkinci koltuk tahtayı ters
/// görür (kendi taşları altta).
class HiddenRanksSkin extends BoardSkin {
  const HiddenRanksSkin();

  static const sides = [Color(0xFFC0392B), Color(0xFF2F6DB5)];
  static const n = HiddenRanksRules.n;

  bool _flip(BoardPaintInfo? info) => info != null && info.viewer == 1;

  int _cell(int i, bool flip) => flip ? n * n - 1 - i : i;

  Rect _rect(Size size, int i, bool flip) {
    final k = _cell(i, flip);
    final w = size.width / n, h = size.height / n;
    return Rect.fromLTWH(k % n * w, k ~/ n * h, w, h);
  }

  static void drawRank(Canvas c, Rect r, int rk, Color ink) {
    final o = r.center;
    final u = r.width;
    if (rk == HiddenRanksRules.flag) {
      // Yuva: dallardan çanak ve içinde yumurta.
      c.drawOval(Rect.fromCenter(center: o.translate(0, u * 0.12), width: u * 0.62, height: u * 0.3), Paint()..color = const Color(0xFF8D6E3F));
      c.drawOval(Rect.fromCenter(center: o.translate(0, -u * 0.04), width: u * 0.26, height: u * 0.32), Paint()..color = const Color(0xFFFFF8E7));
      final tw = Paint()
        ..color = const Color(0xFF5D4422)
        ..strokeWidth = u * 0.04
        ..style = PaintingStyle.stroke;
      c.drawArc(Rect.fromCenter(center: o.translate(0, u * 0.12), width: u * 0.62, height: u * 0.3), 0, math.pi, false, tw);
      return;
    }
    if (rk == HiddenRanksRules.trap) {
      // Kapan: dişli çember.
      final p = Path();
      for (var k = 0; k < 16; k++) {
        final a = k * math.pi / 8;
        final rad = k.isEven ? u * 0.3 : u * 0.18;
        final pt = o + Offset(math.cos(a), math.sin(a)) * rad;
        if (k == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      p.close();
      c.drawPath(p, Paint()..color = const Color(0xFF555B66));
      c.drawCircle(o, u * 0.1, Paint()..color = ink);
      return;
    }
    final tp = TextPainter(
      text: TextSpan(text: '$rk', style: TextStyle(color: ink, fontSize: u * 0.44, fontWeight: FontWeight.w900, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o - Offset(tp.width / 2, tp.height / 2 + u * 0.04));
    // Rütbe kadar küçük nokta (rakam okunmasa da ayırt edilsin).
    final dots = rk == HiddenRanksRules.spy ? 0 : (rk - 1).clamp(0, 9);
    final dp = Paint()..color = ink.withValues(alpha: 0.7);
    for (var k = 0; k < dots; k++) {
      c.drawCircle(Offset(r.left + u * (0.16 + k * 0.076), r.bottom - u * 0.14), u * 0.025, dp);
    }
    if (rk == HiddenRanksRules.spy) {
      // Fare: küçük kulaklar.
      c.drawCircle(o.translate(-u * 0.2, -u * 0.26), u * 0.07, dp);
      c.drawCircle(o.translate(u * 0.2, -u * 0.26), u * 0.07, dp);
    }
  }

  void _tile(Canvas c, Rect cell, int v, bool open, BoardPaintInfo info) {
    final r = cell.deflate(cell.width * 0.08);
    final side = sides[HiddenRanksRules.owner(v)];
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.16));
    c.drawRRect(rr.shift(Offset(0, r.width * 0.05)), Paint()..color = Colors.black.withValues(alpha: 0.3));
    c.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(side, Colors.white, 0.25)!, Color.lerp(side, Colors.black, 0.2)!])
              .createShader(r));
    if (open) {
      final face = RRect.fromRectAndRadius(r.deflate(r.width * 0.1), Radius.circular(r.width * 0.1));
      c.drawRRect(face, Paint()..color = const Color(0xFFFFF6E5));
      drawRank(c, face.outerRect, HiddenRanksRules.rank(v), Color.lerp(side, Colors.black, 0.35)!);
      if (HiddenRanksRules.revealed(v)) {
        c.drawCircle(Offset(r.right - r.width * 0.14, r.top + r.width * 0.14), r.width * 0.07, Paint()..color = kHighlight);
      }
    } else {
      // Arka yüz: kabartma baklava.
      final o = r.center, h = r.width * 0.28;
      c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - h)
            ..lineTo(o.dx + h, o.dy)
            ..lineTo(o.dx, o.dy + h)
            ..lineTo(o.dx - h, o.dy)
            ..close(),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    if (info.colorBlind) drawMark(c, Offset(r.left + r.width * 0.18, r.top + r.width * 0.18), r.width * 0.14, HiddenRanksRules.owner(v));
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as GridState;
    final flip = _flip(info);
    final over = s.vars[0] == 1;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFF3E7D3A));
    for (var i = 0; i < n * n; i++) {
      final cell = _rect(size, i, flip);
      final v = s.cells[i];
      if ((i % n + i ~/ n).isEven) c.drawRect(cell, Paint()..color = const Color(0xFF4A8C44));
      if (v == -2) {
        c.drawRRect(RRect.fromRectAndRadius(cell.deflate(1), Radius.circular(cell.width * 0.3)), Paint()..color = const Color(0xFF3A86C8));
        final wave = Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell.width * 0.04;
        c.drawArc(Rect.fromCenter(center: cell.center, width: cell.width * 0.5, height: cell.width * 0.25), math.pi, math.pi, false, wave);
        continue;
      }
      if (v >= 0) {
        final open = over || HiddenRanksRules.revealed(v) || HiddenRanksRules.owner(v) == info.viewer;
        _tile(c, cell, v, open, info);
      }
      if (s.last == i) {
        c.drawRect(
            cell.deflate(1),
            Paint()
              ..color = kHighlight.withValues(alpha: 0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      if (info.selected == i) {
        c.drawRRect(
            RRect.fromRectAndRadius(cell.deflate(2), Radius.circular(cell.width * 0.18)),
            Paint()
              ..color = const Color(0xFF7CFC7C)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2, cell.width * 0.07));
      }
      if (info.targets.contains(i)) drawTarget(c, cell.center, cell.width * (v >= 0 ? 0.16 : 0.12));
      if (info.hintFrom == i || info.hintTo == i) drawHint(c, cell);
    }
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final c = (p.dx / size.width * n).floor(), r = (p.dy / size.height * n).floor();
    if (c < 0 || r < 0 || c >= n || r >= n) return -1;
    return _cell(r * n + c, _flip(info));
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    final rr = RRect.fromRectAndRadius(r.deflate(r.width * 0.08), Radius.circular(r.width * 0.16));
    c.drawRRect(rr, Paint()..color = sides[seat]);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.36, seat);
  }
}
