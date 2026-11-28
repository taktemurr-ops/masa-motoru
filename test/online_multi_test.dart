// Çok istemcili çevrimiçi masa: 2–4 başsız istemci aynı masaya oturur ve
// gerçek tahta görünümüyle (BoardView) maçı sonuna kadar oynar.
// Ağ: studio_core'un bellek içi sunucusu (Firestore düzeni ve kurallarının
// aynısı). Oyuncular sıra süresi dolunca (TurnClock) yapay zekâyla oynar;
// botları ev sahibi oynar. Kopma → bot devralması → geri dönüş, uygulamanın
// kapanıp açılması, gecikme ve Arapça (RTL) masa da denenir.
@Tags(['online'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/turn_clock.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/online/online.dart';
import 'package:studio_core/online/online_service.dart';
import 'package:studio_core/online/online_testing.dart';

PlayContext _ctx(GeneratedLevel gl, OnlineMatchLink link, String lang, void Function(RoundResult) fin) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D)],
      background: const [Color(0xFF1A2E5C), Color(0xFF3A6FC4)],
      colorBlind: false,
      reducedMotion: true,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: fin,
      saveResume: (_) {},
      requestHint: () async => false,
      requestBooster: () async => false,
      requestContinue: () async => false,
      sfx: (_) {},
      // PlayScreen'in çevrimiçi koltuk rolleri ile aynı.
      seats: [
        for (var i = 0; i < link.names.length; i++)
          i == link.mySeat ? SeatRole.local : (link.names[i].isEmpty ? SeatRole.ai : SeatRole.remote)
      ],
      match: link,
    );

class _Case {
  final String name;
  final GameRules rules;
  final int seats, humans;
  final Widget Function(PlayContext) view;
  const _Case(this.name, this.rules, this.seats, this.humans, this.view);
}

final _cases = [
  _Case('Tavla 2', MasaPresets.tavla('oyun-tavla'), 2, 2, (c) => BoardView(ctx: c, skin: const TavlaSkin())),
  _Case('Kızma Birader 2+2 bot', MasaPresets.kizma('oyun-kizma-birader'), 4, 2, (c) => BoardView(ctx: c, skin: const KizmaSkin())),
  _Case('Satranç 2', MasaPresets.chess('oyun-satranc'), 2, 2, (c) => BoardView(ctx: c, skin: const ChessSkin())),
  _Case('Emlak Ticareti 3', MasaPresets.property('oyun-emlak-ticareti'), 3, 3, (c) => BoardView(ctx: c, skin: const PropertySkin())),
];

/// Masadaki istemcilerin ekranları (yan yana); null: uygulaması kapalı.
class _Rig {
  final OnlineTestTable t;
  final GeneratedLevel gl;
  final _Case c;
  final String lang;
  final List<OnlineMatchLink?> links;
  final List<int> gen;
  final List<RoundResult?> results;
  _Rig(this.t, this.gl, this.c, this.lang)
      : links = [for (var i = 0; i < t.matches.length; i++) t.link(i)],
        gen = List.filled(t.matches.length, 0),
        results = List.filled(t.matches.length, null) {
    for (var i = 0; i < links.length; i++) {
      watch(i);
    }
  }

  /// Ekranı yeniden kurulacak istemciler (OnlineTable._resync'in aynısı:
  /// hamlesi reddedilen cihaz masayı sunucudaki geçmişten yeniden kurar).
  final Set<int> stale = {};
  int resyncs = 0;

  void watch(int i) {
    final m = links[i]?.m;
    m?.rejections.listen((_) async {
      if (links[i]?.m != m || resyncs > 20) return;
      final fresh = await t.backends[i].rejoin(t.matchId, ended: true);
      if (fresh == null) return;
      t.matches[i] = fresh;
      links[i] = OnlineMatchLink(fresh);
      gen[i]++;
      resyncs++;
      stale.add(i);
      watch(i);
    });
  }

  Widget build() => MaterialApp(
        home: Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: Row(children: [
            for (var i = 0; i < links.length; i++)
              Expanded(
                child: links[i] == null
                    ? const SizedBox()
                    : KeyedSubtree(
                        key: ValueKey('c$i-${gen[i]}'),
                        child: c.view(_ctx(gl, links[i]!, lang, (r) => results[i] = r)),
                      ),
              ),
          ]),
        ),
      );

  bool get done => t.status == MatchStatus.done && [for (var i = 0; i < links.length; i++) if (links[i] != null) results[i]].every((r) => r != null);
}

Future<_Rig> _open(WidgetTester tester, _Case c, {String lang = 'tr', List<String>? names}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(420.0 * c.humans, 820);
  addTearDown(tester.view.reset);
  TurnClock.seconds = 1;
  BoardView.syncAi = true;
  final t = await OnlineTestTable.open(gameId: c.rules.gameId, seats: c.seats, humans: c.humans, names: names);
  final spec = LevelPlanner(gameId: c.rules.gameId, optionalMechanics: const []).run(GameModeId.online, t.seed, difficulty: 4);
  final gl = c.rules.build(spec);
  final rig = _Rig(t, gl, c, lang);
  await tester.pumpWidget(rig.build());
  return rig;
}

Future<void> _play(WidgetTester tester, _Rig rig, {int maxSeconds = 3600, Future<void> Function(int sec)? at}) async {
  var ms = 0;
  while (!rig.done && ms < maxSeconds * 1000) {
    await tester.pump(const Duration(milliseconds: 250));
    ms += 250;
    if (rig.stale.isNotEmpty) {
      rig.stale.clear();
      await tester.pumpWidget(rig.build());
    }
    if (at != null && ms % 1000 == 0) await at(ms ~/ 1000);
  }
  expect(rig.done, isTrue, reason: '${rig.c.name}: maç ${maxSeconds}s içinde bitmedi (hamle: ${rig.t.moveCount})');
  // Herkes aynı kazananı görür: kazanan/kaybeden bayrakları masa sonucuyla tutarlı.
  final w = rig.t.winner;
  expect(w, greaterThanOrEqualTo(-1));
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  tearDown(() {
    TurnClock.seconds = 30;
    BoardView.syncAi = false;
  });

  for (final c in _cases) {
    testWidgets('${c.name}: maç sonuna kadar, herkes aynı masayı görür', (tester) async {
      final rig = await _open(tester, c);
      await _play(tester, rig);
      expect(rig.t.rejected, isEmpty, reason: 'kural dışı/çakışan yazma olmamalı');
    });
  }

  testWidgets('Tavla: kopma → ev sahibi botla oynar → geri dönüş', (tester) async {
    final rig = await _open(tester, _cases[0]);
    var dropped = false, back = false;
    await _play(tester, rig, at: (sec) async {
      if (sec == 6 && !dropped) {
        dropped = true;
        rig.t.drop(1);
      }
      if (sec == 9 && dropped && !back) rig.t.advance(const Duration(seconds: 50));
      if (sec == 40 && !back) {
        back = true;
        await rig.t.back(1);
      }
    });
  });

  testWidgets('Kızma Birader: uygulama kapanıp açılır, geçmiş hamlelerle sürer', (tester) async {
    final rig = await _open(tester, _cases[1]);
    var killed = false, resumed = false;
    await _play(tester, rig, at: (sec) async {
      if (sec == 8 && !killed) {
        killed = true;
        rig.t.kill(1);
        rig.links[1] = null;
        await tester.pumpWidget(rig.build());
        rig.t.advance(const Duration(seconds: 50));
      }
      if (sec == 30 && killed && !resumed) {
        resumed = true;
        final l = await rig.t.resume(1);
        if (l != null) {
          rig.links[1] = l;
          rig.watch(1);
          rig.gen[1]++;
          await tester.pumpWidget(rig.build());
        }
      }
    });
  });

  testWidgets('Tavla: gecikme (40 ms) ve Arapça (RTL) masa', (tester) async {
    final rig = await _open(tester, _cases[0], lang: 'ar', names: ['نسر', 'Mavi Tilki']);
    rig.t.latency = const Duration(milliseconds: 40);
    await _play(tester, rig);
  });
}
