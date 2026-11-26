import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'board_view.dart';
import 'skins.dart';

// ======================================================================
// Kartlı Beşleme: elden kart oynayıp tahtadaki karşılığına pul koyarak
// beşli dizi kurma. Tahta yerleşimi stüdyoya özgüdür (sabit tohumla
// karıştırılmış; her kart tahtada iki kez, dört köşe herkesin ortak pulu).
// İki deste (104 kart). Vale kartları tahtada yoktur:
//   ♣ ve ♦ Valesi: istediğin boş kareye pul koy (joker),
//   ♠ ve ♥ Valesi: rakibin dizide kilitlenmemiş bir pulunu kaldır.
// İki tahta karşılığı da doluysa kart "ölü"dür: desteye atılıp yenisi
// çekilir. İki kişide iki, üç kişide bir beşli dizi kazanır.
// Kart = renk*13 + değer (0 As … 9 On, 10 Vale, 11 Kız, 12 Papaz).
// Hücre: -2 köşe, -1 boş, p pul, p + 10 dizide kilitli pul.

class CardLineState extends BoardState {
  final int players;
  final List<int> cells; // 100
  final List<int> hands; // players * handSize, -1 boş
  final List<int> deck;

  /// [0] bitti, [1] kazanan + 1, [2] destede sıradaki, [3] art arda pas,
  /// [4..6] oyuncuların dizi sayısı.
  final List<int> vars;
  CardLineState(this.players, this.cells, this.hands, this.deck, this.vars);

  int get handSize => hands.length ~/ players;

  @override
  CardLineState copy() => copyBase(CardLineState(players, List.of(cells), List.of(hands), deck, List.of(vars)));

  @override
  Map<String, Object?> toJson() => {...baseJson(), 'n': players, 'g': cells, 'h': hands, 'd': deck, 'v': vars};

  static CardLineState read(Map<String, dynamic> j) {
    final s = CardLineState((j['n'] as num).toInt(), intList(j['g']), intList(j['h']), intList(j['d']), intList(j['v']));
    s.readBase(j);
    return s;
  }
}

class CardLineRules extends BoardRules<CardLineState> {
  final int seats;
  const CardLineRules([this.seats = 2]);

  @override
  String get id => 'card_line';

  @override
  int get players => seats;

  @override
  int get maxPly => 500;

  /// Şans: destenin sırası. Doğrulama kurulumla yetinir.
  @override
  bool get stochastic => true;

  static const n = 10;
  static const handBase = 200, deadTarget = 150;
  static const corners = {0, 9, 90, 99};

  int get needLines => seats == 2 ? 2 : 1;
  int get handSize => seats == 2 ? 7 : 6;

  static bool isJack(int card) => card % 13 == 10;

  /// ♣ (2) ve ♦ (3) valesi joker; ♠ (0) ve ♥ (1) valesi kaldırır.
  static bool wildJack(int card) => isJack(card) && card ~/ 13 >= 2;
  static bool removeJack(int card) => isJack(card) && card ~/ 13 < 2;

  /// Tahta: köşeler hariç 96 kare, vale dışındaki 48 kartın ikişer kopyası.
  static final List<int> layout = _layout();

  static List<int> _layout() {
    final cards = <int>[
      for (var copy = 0; copy < 2; copy++)
        for (var c = 0; c < 52; c++)
          if (!isJack(c)) c
    ];
    final r = SeededRandom(0x5E9E);
    for (var i = cards.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = cards[i];
      cards[i] = cards[j];
      cards[j] = t;
    }
    final out = List.filled(100, -1);
    var k = 0;
    for (var i = 0; i < 100; i++) {
      if (!corners.contains(i)) out[i] = cards[k++];
    }
    return out;
  }

  static final Map<int, List<int>> spots = () {
    final m = <int, List<int>>{};
    for (var i = 0; i < 100; i++) {
      if (layout[i] >= 0) m.putIfAbsent(layout[i], () => []).add(i);
    }
    return m;
  }();

  @override
  CardLineState initial(SeededRandom r) {
    final deck = <int>[for (var copy = 0; copy < 2; copy++) for (var c = 0; c < 52; c++) c];
    for (var i = deck.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = deck[i];
      deck[i] = deck[j];
      deck[j] = t;
    }
    final cells = List.filled(100, -1);
    for (final c in corners) {
      cells[c] = -2;
    }
    final hs = handSize;
    final hands = List.filled(seats * hs, -1);
    var k = 0;
    for (var i = 0; i < hs; i++) {
      for (var p = 0; p < seats; p++) {
        hands[p * hs + i] = deck[k++];
      }
    }
    return CardLineState(seats, cells, hands, deck, [0, 0, k, 0, 0, 0, 0]);
  }

  static int owner(int v) => v < 0 ? -1 : v % 10;
  static bool locked(int v) => v >= 10;

  bool dead(CardLineState s, int card) => !isJack(card) && spots[card]!.every((i) => s.cells[i] != -1);

  @override
  List<int> moves(CardLineState s) {
    if (isOver(s)) return const [];
    final out = <int>[];
    final p = s.turn, hs = s.handSize;
    final seen = <int>{};
    for (var h = 0; h < hs; h++) {
      final card = s.hands[p * hs + h];
      if (card < 0 || !seen.add(card)) continue;
      final from = handBase + h;
      if (wildJack(card)) {
        for (var i = 0; i < 100; i++) {
          if (s.cells[i] == -1) out.add(mv(from, i));
        }
      } else if (removeJack(card)) {
        for (var i = 0; i < 100; i++) {
          final v = s.cells[i];
          if (v >= 0 && !locked(v) && owner(v) != p) out.add(mv(from, i));
        }
      } else if (dead(s, card)) {
        out.add(mv(from, deadTarget));
      } else {
        for (final i in spots[card]!) {
          if (s.cells[i] == -1) out.add(mv(from, i));
        }
      }
    }
    if (out.isEmpty) out.add(kPass);
    return out;
  }

  static const _dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];

  bool _mine(CardLineState s, int i, int p) => s.cells[i] == -2 || owner(s.cells[i]) == p;

  /// [at] karesine konan pulla oluşan yeni beşli dizileri kilitler.
  int _lockLines(CardLineState s, int at, int p) {
    var made = 0;
    final c0 = at % n, r0 = at ~/ n;
    for (final (dc, dr) in _dirs) {
      // Karenin geçtiği bütün beşli pencereler.
      for (var start = -4; start <= 0; start++) {
        final cells = <int>[];
        for (var k = 0; k < 5; k++) {
          final c = c0 + (start + k) * dc, r = r0 + (start + k) * dr;
          if (c < 0 || r < 0 || c >= n || r >= n) break;
          cells.add(r * n + c);
        }
        if (cells.length < 5 || !cells.every((i) => _mine(s, i, p))) continue;
        // Eski bir diziyle en çok bir pul paylaşılabilir.
        final shared = cells.where((i) => s.cells[i] >= 10).length;
        if (shared > 1) continue;
        for (final i in cells) {
          if (s.cells[i] >= 0 && s.cells[i] < 10) s.cells[i] += 10;
        }
        made++;
        break;
      }
    }
    return made;
  }

  void _draw(CardLineState s, int p, int slot) {
    final hs = s.handSize;
    if (s.vars[2] < s.deck.length) {
      s.hands[p * hs + slot] = s.deck[s.vars[2]++];
    } else {
      s.hands[p * hs + slot] = -1;
    }
  }

  @override
  void apply(CardLineState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m == kPass) {
      s.vars[3]++;
      s.turn = (p + 1) % s.players;
      if (s.vars[3] >= s.players) s.vars[0] = 1;
      return;
    }
    s.vars[3] = 0;
    final slot = mvFrom(m) - handBase, to = mvTo(m);
    final card = s.hands[p * s.handSize + slot];
    if (to == deadTarget) {
      _draw(s, p, slot);
      s.last = -1;
      // Ölü kart değiştirilince sıra yine aynı oyuncudadır.
      return;
    }
    if (removeJack(card)) {
      s.cells[to] = -1;
    } else {
      s.cells[to] = p;
      final made = _lockLines(s, to, p);
      if (made > 0) {
        s.vars[4 + p] += made;
        if (s.vars[4 + p] >= needLines) {
          s.vars[0] = 1;
          s.vars[1] = p + 1;
        }
      }
    }
    s.last = to;
    _draw(s, p, slot);
    s.turn = (p + 1) % s.players;
  }

  @override
  bool isOver(CardLineState s) => s.vars[0] == 1;

  @override
  int winner(CardLineState s) => isOver(s) ? s.vars[1] - 1 : -1;

  /// [p] için karenin değeri: geçtiği beşli pencerelerdeki kendi pulları
  /// (rakip pulu olmayan pencerelerde).
  double cellValue(CardLineState s, int at, int p) {
    var v = 0.0;
    final c0 = at % n, r0 = at ~/ n;
    for (final (dc, dr) in _dirs) {
      for (var start = -4; start <= 0; start++) {
        var mine = 0;
        var ok = true;
        for (var k = 0; k < 5; k++) {
          final c = c0 + (start + k) * dc, r = r0 + (start + k) * dr;
          if (c < 0 || r < 0 || c >= n || r >= n) {
            ok = false;
            break;
          }
          final i = r * n + c;
          if (i == at) continue;
          final x = s.cells[i];
          if (x == -2 || owner(x) == p) {
            mine++;
          } else if (x >= 0) {
            ok = false;
            break;
          }
        }
        if (ok) v += mine >= 4 ? 400 : math.pow(4, mine).toDouble();
      }
    }
    return v;
  }

  double _threat(CardLineState s, int at, int me) {
    var t = 0.0;
    for (var q = 0; q < s.players; q++) {
      if (q != me) t = math.max(t, cellValue(s, at, q));
    }
    return t;
  }

  @override
  int? policy(CardLineState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.length == 1) return ms.first;
    final p = s.turn, hs = s.handSize;
    var best = ms.first;
    var bestV = -double.infinity;
    for (final m in ms) {
      final card = s.hands[p * hs + mvFrom(m) - handBase];
      final to = mvTo(m);
      double v;
      if (to == deadTarget) {
        v = 30;
      } else if (removeJack(card)) {
        final q = owner(s.cells[to]);
        final c = s.copy()..cells[to] = -1;
        v = cellValue(c, to, q) * 0.9 - 60;
      } else {
        v = cellValue(s, to, p) + _threat(s, to, p) * 0.85;
        if (wildJack(card)) v -= 90;
      }
      v += r.nextDouble() * (1 + noise * 120);
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (noise >= 0.6 && r.nextDouble() < (noise - 0.5) * 0.4) return ms[r.nextInt(ms.length)];
    return best;
  }

  @override
  double evaluate(CardLineState s, int player) {
    if (isOver(s)) {
      final w = winner(s);
      return w < 0 ? 0 : (w == player ? 99 : -99);
    }
    var v = 0.0;
    for (var p = 0; p < s.players; p++) {
      v += (p == player ? 30 : -30) * s.vars[4 + p];
    }
    return v.clamp(-95, 95).toDouble();
  }

  @override
  String status(CardLineState s, String lang) {
    final left = s.deck.length - s.vars[2];
    return '${[for (var p = 0; p < s.players; p++) '${p + 1}: ${s.vars[4 + p]}/$needLines'].join('  ·  ')}  ·  ▤ $left';
  }

  @override
  CardLineState fromJson(Map<String, dynamic> j) => CardLineState.read(j);
}

/// Kartlı Beşleme çizimi: keçe tahta üstünde küçük kart yüzleri, renkli
/// pullar; altta ekrana bakan oyuncunun eli ve deste.
class CardLineSkin extends BoardSkin {
  const CardLineSkin();

  static const chips = [Color(0xFF2F6DB5), Color(0xFF2E9B57), Color(0xFFC0392B)];
  static const _felt = Color(0xFF1F5C46);
  static const _ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  static const _suits = ['♠', '♥', '♣', '♦'];

  static const n = CardLineRules.n;

  @override
  double aspect(BoardState s) => 10 / 12.8;

  static bool red(int card) => card ~/ 13 == 1 || card ~/ 13 == 3;

  Rect _cell(Size size, int i) {
    final u = size.width / n;
    return Rect.fromLTWH(i % n * u, i ~/ n * u, u, u);
  }

  Rect _hand(Size size, int k, int count) {
    final u = size.width / n;
    final w = math.min(1.25 * u, 8.2 * u / count);
    return Rect.fromLTWH(0.2 * u + k * w, 10.35 * u, w * 0.94, 2.2 * u);
  }

  Rect _deckRect(Size size) {
    final u = size.width / n;
    return Rect.fromLTWH(8.65 * u, 10.35 * u, 1.2 * u, 2.2 * u);
  }

  void _text(Canvas c, String t, Offset o, double size, Color color, {FontWeight w = FontWeight.w800}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size, fontWeight: w, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
  }

  void _cardFace(Canvas c, Rect r, int card, {bool big = false}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.12));
    c.drawRRect(rr, Paint()..color = const Color(0xFFFFFDF7));
    final ink = red(card) ? const Color(0xFFC0392B) : const Color(0xFF1E2228);
    if (CardLineRules.isJack(card)) {
      _text(c, 'J', r.topCenter + Offset(0, r.height * 0.2), r.width * 0.42, ink);
      _text(c, _suits[card ~/ 13], r.center + Offset(0, r.height * 0.05), r.width * 0.38, ink);
      _text(c, CardLineRules.wildJack(card) ? '+' : '−', r.bottomCenter - Offset(0, r.height * 0.18), r.width * 0.5,
          CardLineRules.wildJack(card) ? const Color(0xFF2E9B57) : const Color(0xFFC0392B));
      return;
    }
    if (big) {
      _text(c, _ranks[card % 13], r.topCenter + Offset(0, r.height * 0.22), r.width * 0.44, ink);
      _text(c, _suits[card ~/ 13], r.center + Offset(0, r.height * 0.18), r.width * 0.5, ink);
    } else {
      _text(c, _ranks[card % 13], r.center - Offset(0, r.height * 0.16), r.width * 0.36, ink);
      _text(c, _suits[card ~/ 13], r.center + Offset(0, r.height * 0.22), r.width * 0.32, ink);
    }
  }

  void _back(Canvas c, Rect r) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.12));
    c.drawRRect(rr, Paint()..color = const Color(0xFF7A2E2A));
    c.drawRRect(
        rr.deflate(r.width * 0.1),
        Paint()
          ..color = const Color(0xFFE9C46A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  void paint(Canvas c, Size size, BoardState st, BoardPaintInfo info) {
    final s = st as CardLineState;
    final u = size.width / n;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = _felt);
    for (var i = 0; i < 100; i++) {
      final r = _cell(size, i).deflate(u * 0.04);
      final v = s.cells[i];
      if (CardLineRules.corners.contains(i)) {
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.12)), Paint()..color = const Color(0xFFE9C46A));
        _text(c, '★', r.center, r.width * 0.6, const Color(0xFF7A2E2A));
        continue;
      }
      _cardFace(c, r, CardLineRules.layout[i]);
      if (v >= 0) {
        final o = r.center;
        drawDisc(c, o, r.width * 0.36, chips[CardLineRules.owner(v) % chips.length], ring: CardLineRules.locked(v));
        if (info.colorBlind) drawMark(c, o, r.width * 0.3, CardLineRules.owner(v) % 2);
      }
      if (s.last == i) {
        c.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.12)),
            Paint()
              ..color = kHighlight
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      if (info.targets.contains(i)) drawTarget(c, r.center, r.width * 0.16);
      if (info.hintTo == i) drawHint(c, r);
    }
    // El.
    final me = info.viewer >= 0 && info.viewer < s.players ? info.viewer : -1;
    final hs = s.handSize;
    for (var k = 0; k < hs; k++) {
      final r = _hand(size, k, hs);
      final card = me >= 0 ? s.hands[me * hs + k] : 0;
      if (me >= 0 && card < 0) continue;
      if (me < 0) {
        _back(c, r);
        continue;
      }
      final lift = info.selected == CardLineRules.handBase + k ? -u * 0.18 : 0.0;
      final rr = r.shift(Offset(0, lift));
      _cardFace(c, rr, card, big: true);
      final dead = !CardLineRules.isJack(card) && CardLineRules.spots[card]!.every((i) => s.cells[i] != -1);
      if (dead) {
        c.drawRRect(RRect.fromRectAndRadius(rr, Radius.circular(rr.width * 0.12)), Paint()..color = Colors.black.withValues(alpha: 0.35));
      }
      if (info.selected == CardLineRules.handBase + k) {
        c.drawRRect(
            RRect.fromRectAndRadius(rr.inflate(1.5), Radius.circular(rr.width * 0.14)),
            Paint()
              ..color = const Color(0xFF7CFC7C)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
      if (info.hintFrom == CardLineRules.handBase + k) drawHint(c, rr.inflate(2));
    }
    final dr = _deckRect(size);
    final left = s.deck.length - s.vars[2];
    if (left > 0) _back(c, dr);
    _text(c, '$left', dr.center, u * 0.42, Colors.white);
    if (info.targets.contains(CardLineRules.deadTarget)) drawHint(c, dr.inflate(2));
  }

  @override
  int hit(Offset p, Size size, BoardState st, [BoardPaintInfo? info]) {
    final s = st as CardLineState;
    final u = size.width / n;
    if (p.dy < 10 * u) {
      final c = (p.dx / u).floor(), r = (p.dy / u).floor();
      return c >= 0 && r >= 0 && c < n && r < n ? r * n + c : -1;
    }
    if (_deckRect(size).inflate(4).contains(p)) return CardLineRules.deadTarget;
    for (var k = 0; k < s.handSize; k++) {
      if (_hand(size, k, s.handSize).inflate(2).contains(p)) return CardLineRules.handBase + k;
    }
    return -1;
  }

  @override
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info) {
    drawDisc(c, r.center, r.width * 0.42, chips[seat % chips.length], ring: true);
    if (info.colorBlind) drawMark(c, r.center, r.width * 0.42, seat % 2);
  }
}
