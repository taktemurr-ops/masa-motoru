import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:masa_motoru/src/studio_chrome.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

PlayContext _ctx(GeneratedLevel gl, String lang) => PlayContext(
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
      finish: (_) {},
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

/// Oyun ekranının sarmalayıcısı: oyun alanı eski (açık) temayla, palet tema
/// uzantısıyla gelir (studio-core play.dart gibi).
Widget _host(Widget child, {StudioLook look = const StudioLook()}) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light, extensions: [look]),
      home: Scaffold(body: SafeArea(child: child)),
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Görünümdeki bütün yazılar: koyu stüdyo zemininde okunur olmalı (siyah
/// yazı yalnız kendi açık zeminini çizen hap/rozetlerde olur).
void _expectLightText(WidgetTester t) {
  final ok = {StudioChoice, StudioSeatBadge, StudioButton};
  for (final e in find.byType(RichText).evaluate()) {
    final r = e.renderObject as RenderParagraph;
    final c = r.text.style?.color;
    if (c == null) continue;
    // Vurgu zeminli haplarda yazı, vurguya göre seçilen renktir (onAccent).
    if (c == StudioLook.of(e).onAccent) continue;
    var inside = false;
    e.visitAncestorElements((a) {
      if (ok.contains(a.widget.runtimeType)) {
        inside = true;
        return false;
      }
      return true;
    });
    if (inside) continue;
    expect(c.computeLuminance(), greaterThan(0.35), reason: 'koyu zeminde okunmayan yazı: "${r.text.toPlainText()}"');
  }
}

Future<void> _tapAround(WidgetTester t) async {
  final size = t.view.physicalSize / t.view.devicePixelRatio;
  for (var y = 80.0; y < size.height - 10; y += size.height / 7) {
    for (var x = 30.0; x < size.width; x += size.width / 4) {
      await t.tapAt(Offset(x, y));
      await t.pump(const Duration(milliseconds: 150));
    }
  }
}

void main() {
  final cases = <String, (BoardGameRules, BoardSkin)>{
    'satranc': (MasaPresets.chess('t-satranc'), const ChessSkin()),
    'mangala': (MasaPresets.mancala('t-mangala', MancalaRules.mangala), const MancalaSkin()),
    'reversi': (MasaPresets.reversi('t-reversi'), const DiscSkin(DiscBoard.wood, kBlackWhite)),
    'tavla': (MasaPresets.tavla('t-tavla'), const TavlaSkin()),
    'go': (MasaPresets.go('t-go'), const DiscSkin(DiscBoard.felt, kBlackWhite)),
  };

  for (final e in cases.entries) {
    for (final lang in const ['tr', 'ar']) {
      testWidgets('${e.key} ($lang): tahta onaylı tasarımın arayüzüyle açılır', (t) async {
        t.view.physicalSize = const Size(1080, 2280);
        t.view.devicePixelRatio = 2.75;
        addTearDown(t.view.reset);
        final (rules, skin) = e.value;
        final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
        final gl = rules.build(planner.spec(3));
        await t.pumpWidget(_host(Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: BoardView(ctx: _ctx(gl, lang), skin: skin),
        )));
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
        final inner = t.element(find.descendant(of: find.byType(StudioChrome), matching: find.byType(LayoutBuilder)).first);
        expect(Theme.of(inner).brightness, Brightness.dark);
        expect(find.byType(StudioRoundAction), findsWidgets);
        expect(find.byType(StudioTag), findsOneWidget);
        _expectLightText(t);
        await _tapAround(t);
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      });
    }
  }

  testWidgets('sıra hapı ve pas düğmesi koyu paletlerde okunur', (t) async {
    for (final look in [const StudioLook(), StudioLook.fromSeed(const Color(0xFF8A5A36))]) {
      expect(_contrast(look.onAccent, look.accent), greaterThan(4.5));
      expect(_contrast(kStudioText, look.base), greaterThan(7));
      await t.pumpWidget(_host(look: look, StudioChrome(child: StudioChoice(label: 'Pas', onPressed: () {}))));
      expect(t.takeException(), isNull);
    }
  });
}
