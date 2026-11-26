/// Motor içi arayüz parçaları onaylı merkez tasarımıyla (studio_ui).
///
/// Oyun alanı (tahta, kart, taş çizimleri) kendi sanatını korur; üstündeki
/// koltuk etiketleri, ihale/koz seçicileri, puan tabloları, diyaloglar ve
/// düğmeler [StudioLook] paletinden çizilir. [StudioChrome] alt ağaca
/// koyu stüdyo temasını verir: içeriden açılan diyalog ve alt sayfalar da
/// (`showDialog` / `showModalBottomSheet` temayı yakalar) aynı görünümü alır.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/app/studio_ui.dart';

export 'package:studio_core/app/studio_ui.dart';

/// Koyu zemin üstünde okunur ana yazı rengi.
const kStudioText = Colors.white;

/// Koyu zemin üstünde ikincil yazı rengi.
const kStudioTextDim = Color(0xFFC9CCE4);

StudioLook? _lastLook;
ThemeData? _lastTheme;

/// Ağaçtaki paletin koyu stüdyo teması (son palet için önbellekli).
ThemeData studioThemeOf(BuildContext context) {
  final look = StudioLook.of(context);
  if (_lastTheme == null || _lastLook != look) {
    _lastLook = look;
    _lastTheme = buildStudioTheme(look);
  }
  return _lastTheme!;
}

/// Alt ağaca onaylı tasarımın koyu temasını verir.
class StudioChrome extends StatelessWidget {
  final Widget child;
  const StudioChrome({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = studioThemeOf(context);
    return Theme(
      data: theme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: kStudioText),
        child: IconTheme.merge(data: const IconThemeData(color: kStudioText), child: child),
      ),
    );
  }
}

/// Oyun alanının üstünde duran opak panel (ihale, sözleşme, puan tablosu).
class StudioBoardPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  const StudioBoardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return StudioPanel(
      margin: margin,
      padding: padding,
      radius: 22,
      onTap: onTap,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [look.sheet.withValues(alpha: 0.96), look.base.withValues(alpha: 0.96)],
      ),
      child: DefaultTextStyle.merge(style: const TextStyle(color: kStudioText), child: child),
    );
  }
}

/// Koltuk / oyuncu etiketi: koyu yarı saydam hap, sırası gelende vurgu kenarı.
class StudioSeatBadge extends StatelessWidget {
  final String title;
  final String? detail;
  final bool active;
  final Widget? extra;
  const StudioSeatBadge({super.key, required this.title, this.detail, this.active = false, this.extra});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active
            ? LinearGradient(colors: [look.accent.withValues(alpha: 0.85), look.play.withValues(alpha: 0.85)])
            : null,
        color: active ? null : Colors.black.withValues(alpha: 0.38),
        border: Border.all(
          color: active ? Colors.white.withValues(alpha: 0.85) : look.accent.withValues(alpha: 0.45),
          width: active ? 2 : 1.2,
        ),
        boxShadow: active
            ? [BoxShadow(color: look.accent.withValues(alpha: 0.45), blurRadius: 12)]
            : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          title,
          style: TextStyle(
            color: active ? look.onAccent : kStudioText,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (detail != null && detail!.isNotEmpty)
          Text(
            detail!,
            style: TextStyle(
              fontSize: 12,
              color: active ? look.onAccent.withValues(alpha: 0.9) : kStudioTextDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (extra != null) extra!,
      ]),
    );
  }
}

/// Küçük bilgi hapı (koz, süre, puan).
class StudioTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;
  final TextStyle? style;
  const StudioTag({super.key, required this.text, this.icon, this.iconColor, this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.black.withValues(alpha: 0.32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor ?? kStudioText),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 13).merge(style),
        ),
      ]),
    );
  }
}

/// Seçim düğmesi (ihale, sözleşme, eylem): hap biçimli, en az 46 piksel.
/// [hinted] ipucu verilen seçeneği altınla işaretler.
class StudioChoice extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool hinted;
  final bool selected;
  final IconData? icon;
  const StudioChoice({
    super.key,
    required this.label,
    this.onPressed,
    this.hinted = false,
    this.selected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    final enabled = onPressed != null;
    final Color fg;
    final Gradient? g;
    final Color? fill;
    if (hinted) {
      g = const LinearGradient(colors: [Color(0xFFFFE08A), Color(0xFFFFC14A)]);
      fill = null;
      fg = const Color(0xFF2A1E05);
    } else if (selected) {
      g = null;
      fill = look.accent;
      fg = look.onAccent;
    } else {
      g = LinearGradient(colors: [
        Color.lerp(look.card, Colors.white, 0.08)!,
        Color.lerp(look.card, look.base, 0.35)!,
      ]);
      fill = null;
      fg = kStudioText;
    }
    final r = BorderRadius.circular(23);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          borderRadius: r,
          child: InkWell(
            borderRadius: r,
            onTap: onPressed,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: g,
                color: fill,
                border: Border.all(
                  color: hinted ? StudioLook.gold : look.accent.withValues(alpha: selected ? 1 : 0.55),
                  width: 1.2,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 30, minWidth: 30),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sırayla oynamada eli kapatan kart: "Telefonu Oyuncu 2'ye ver".
class StudioCover extends StatelessWidget {
  final String text;
  final String sub;
  final double? height;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;
  const StudioCover({
    super.key,
    required this.text,
    required this.sub,
    required this.onTap,
    this.height,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Semantics(
      button: true,
      label: text,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          margin: margin,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: look.tile,
            border: Border.all(color: look.accent.withValues(alpha: 0.6), width: 1.4),
          ),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.swap_horiz_rounded, color: look.accent, size: 28),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800),
            ),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: kStudioTextDim)),
          ]),
        ),
      ),
    );
  }
}

/// Yuvarlak araç düğmesi (ipucu, geri al): koyu hap, beyaz simge.
class StudioRoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const StudioRoundAction({super.key, required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Ink(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.32),
                  border: Border.all(color: look.accent.withValues(alpha: 0.6), width: 1.4),
                ),
                child: Icon(icon, color: kStudioText, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
