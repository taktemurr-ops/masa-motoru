import 'dart:convert';

import 'package:studio_core/core/rng.dart';

/// Hamle: tek tamsayı. [from] -1 ise yerleştirme hamlesidir.
/// Bit düzeni: extra << 20 | (from + 1) << 10 | to. Kare sayısı en çok 1022.
int mv(int from, int to, [int extra = 0]) => (extra << 20) | ((from + 1) << 10) | to;
int mvFrom(int m) => ((m >> 10) & 1023) - 1;
int mvTo(int m) => m & 1023;
int mvExtra(int m) => m >> 20;

/// Pas hamlesi (oynanacak hamle yokken).
const kPass = 1023;

/// Bütün masa oyunlarının durumu. [turn] sıradaki oyuncu, [ply] oynanan hamle.
abstract class BoardState {
  int turn = 0;
  int ply = 0;
  int last = -1; // son hamle (çizimde vurgulanır)

  BoardState copy();
  Map<String, Object?> toJson();

  /// Ortak alanları kopyala (alt sınıfların copy() içinde kullanılır).
  T copyBase<T extends BoardState>(T c) {
    c
      ..turn = turn
      ..ply = ply
      ..last = last;
    return c;
  }

  Map<String, Object?> baseJson() => {'t': turn, 'p': ply, 'l': last};
  void readBase(Map<String, dynamic> j) {
    turn = (j['t'] as num).toInt();
    ply = (j['p'] as num).toInt();
    last = (j['l'] as num?)?.toInt() ?? -1;
  }

  String serialize() => jsonEncode(toJson());
}

List<int> intList(Object? o) => [for (final x in o as List) (x as num).toInt()];

/// Bir masa oyununun kuralları. İki kişilik, tam bilgili oyunlarda yapay
/// zekâ alfa-beta araması kullanır; zarlı/çok oyunculu oyunlar [stochastic]
/// ile benzetim tabanlı aramaya geçer.
abstract class BoardRules<S extends BoardState> {
  const BoardRules();

  /// Oyunun kimliği (kayıt ve çizim için).
  String get id;
  int get players => 2;

  S initial(SeededRandom r);
  List<int> moves(S s);

  /// Hamleyi uygular (durumu değiştirir); [turn], [ply] ve [last]'ı da günceller.
  void apply(S s, int m);
  bool isOver(S s);

  /// Kazanan oyuncu; berabere ya da bitmemişse -1.
  int winner(S s);

  /// [player] açısından sezgisel değer, yaklaşık -100..100.
  double evaluate(S s, int player);

  S fromJson(Map<String, dynamic> j);
  S parse(String str) => fromJson(jsonDecode(str) as Map<String, dynamic>);

  /// Arama sırasında önce denenecek hamleler (büyük önce).
  int moveOrder(S s, int m) => 0;

  /// Büyük tahtalarda aramaya sokulacak aday hamleler.
  List<int> searchMoves(S s) => moves(s);

  /// Elle yazılmış oyun politikası (zar oyunları gibi aramanın pahalı ya da
  /// anlamsız olduğu yerlerde). [noise] 0 güçlü, 1 zayıf. null: arama kullan.
  int? policy(S s, double noise, SeededRandom r) => null;

  /// Zar gibi şans olayları.
  bool get stochastic => false;
  bool needsChance(S s) => false;
  void applyChance(S s, SeededRandom r) {}

  /// Doğrulamada erken karar: oyuncunun değerlendirmesi bu eşiği geçerse
  /// (uzun oyunlarda) maç kazanılmış sayılır.
  double get decisive => double.infinity;

  /// Sonsuz oyunlara karşı: bu kadar hamleden sonra berabere sayılır.
  int get maxPly => 400;

  /// Oyun sürerken ekranda gösterilecek kısa durum (skor, taş sayısı…).
  String status(S s, String lang) => '';
}

/// Ortak sonuç: [player] kazandı mı, berabere mi.
enum Outcome { win, draw, loss }

Outcome outcomeFor<S extends BoardState>(BoardRules<S> rules, S s, int player) {
  final w = rules.winner(s);
  if (w == player) return Outcome.win;
  if (w < 0) return Outcome.draw;
  return Outcome.loss;
}
