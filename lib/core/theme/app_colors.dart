import 'package:flutter/material.dart';

/// Plateau Eye brand colour palette — Oxford Navy, Highland Emerald, Warm Gold.
///
/// THE THREE ANCHORS BELOW ARE THE LOGO'S OWN INK, sampled from
/// `Plateau_Eye_Logo.png`: `#0B234B` is the ring and the wordmark, `#0F6C32`
/// is the Plateau State silhouette, `#B99123` is the inner ring.
/// `scripts/check_brand_colours.py` re-samples that file on every push and
/// fails if a token here drifts from it — so the palette cannot quietly stop
/// matching the mark.
///
/// Nothing outside this file may name a colour. The app shipped a crimson
/// SOS button that faded to magenta, an indigo-to-cyan voice button, ten
/// per-category pastels (orange, cobalt, purple, pink, brown, teal) and a
/// slate dashboard left from an older console — none of it in the brand, all
/// of it written straight into the widgets where no palette change could
/// reach it. The same check now refuses a colour literal anywhere in `lib/`
/// but here.
class AppColors {
  AppColors._();

  // Core Palette (Plateau Eye: Oxford Navy, Highland Emerald, Warm Gold)
  /// Background
  static const Color background = Color(0xFFFAFAF7); // Crisp Warm White
  /// Surface
  static const Color surface = Color(0xFFFFFFFF); // Pure White
  /// Surface Light
  static const Color surfaceLight = Color(0xFFF4F5F0);

  /// The ambient wash behind the home screen: [background] with a breath of
  /// Oxford Navy in it, blended to an OPAQUE value on purpose.
  ///
  /// It used to be a gradient from `primary.withValues(alpha: 0.03)` to
  /// `background`. Lerping a 3%-alpha navy to an opaque off-white runs the
  /// midpoint through roughly 50% alpha AND halfway to navy — a muddy
  /// blue-grey — and at `radius: 1.5` that midpoint is most of the screen.
  /// The citizen home screen, the one a person opens first, was `#C1C7CE`
  /// instead of `#FAFAF7`: it looked like a disabled screen, and nothing in
  /// the palette said so. A gradient's stops must be opaque, or all
  /// translucent; never one of each.
  static const Color ambientWash = Color(0xFFF3F4F6);

  /// Primary Brand Color: Oxford Navy
  static const Color primary = Color(0xFF0B234B); // Oxford Navy
  /// Deep Navy
  static const Color primaryDark = Color(0xFF06142C);
  /// Medium Navy
  static const Color primaryLight = Color(0xFF163B72);

  /// Highland Emerald Green
  static const Color emerald = Color(0xFF0F6C32);
  /// Light Emerald
  static const Color emeraldLight = Color(0xFF1E8244);

  /// Warm Gold Accent
  static const Color gold = Color(0xFFB99123);

  // ── Status palette ────────────────────────────────────────────────────
  //
  // ONE red, not four. The app had `#D32F2F` in the tokens, `#FF1744` and
  // `#880E4F` in the SOS button, `#C2185B` in the voice dialog, `#B71C1C` on
  // one category and `Colors.redAccent` in the report form. Red is kept —
  // this is an emergency app and the convention is a safety feature, not a
  // style choice — but it is one deliberate red, deep enough to sit beside
  // Oxford Navy instead of vibrating against it.

  /// Emergency / critical alert. White text on this reaches 6.5:1.
  static const Color danger = Color(0xFFB3261E);

  /// The dark end of the emergency gradient, and pressed states.
  static const Color dangerDeep = Color(0xFF7A1710);

  /// A danger fill behind dark text.
  static const Color dangerTint = Color(0xFFFBE4E2);

  /// Warning. The Material orange that was here (`#FF9800`) belongs to no
  /// part of the mark; this is the brand gold darkened until text on white
  /// clears 4.5:1, which `#B99123` itself does not (2.8:1).
  static const Color warning = Color(0xFF7E6112);

  /// A gold fill behind dark text.
  static const Color goldTint = Color(0xFFF6ECD2);

  /// A navy fill behind dark text.
  static const Color navyTint = Color(0xFFE6EAF1);

  /// An emerald fill behind dark text.
  static const Color emeraldTint = Color(0xFFDDEEE2);

  /// Emerald, darkened for text on a light fill.
  static const Color emeraldDeep = Color(0xFF0B5027);

  /// Success / Clear (Highland Emerald)
  static const Color success = Color(0xFF0F6C32);
  /// Info / Intelligence (Oxford Navy)
  static const Color info = Color(0xFF0B234B);

  // Content Palette
  /// Documentation for this public member.
  static const Color onBackground = Color(0xFF1A1A1A); // Dark Grey Text
  /// Documentation for this public member.
  static const Color onSurface = Color(0xFF212121);

  /// Documentation for this public member.
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// Documentation for this public member.
  static const Color textSecondary = Color(0xFF616161);

  /// Documentation for this public member.
  static const Color textDim = Color(0xFF9E9E9E);

  // Outlines & Dividers
  /// Documentation for this public member.
  static const Color outline = Color(0xFFE0E0E0);

  /// Documentation for this public member.
  static const Color outlineVariant = Color(0xFFEEEEEE);

  // HUD Elements (Light HUD)
  /// Documentation for this public member.
  static const BoxBorder hudBorder = Border.fromBorderSide(
    BorderSide(color: Color(0x1A000000)),
  );

  /// Documentation for this public member.

  static const Decoration hudSurface = BoxDecoration(
    color: Color(0x0A000000),
    borderRadius: BorderRadius.all(Radius.circular(12)),
    border: hudBorder,
  );

  // Surface Containers
  /// Documentation for this public member.
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);

  /// Documentation for this public member.
  static const Color surfaceContainerLow = Color(0xFFF7F7F7);

  /// Documentation for this public member.
  static const Color surfaceContainer = Color(0xFFF0F0F0);

  /// Documentation for this public member.
  static const Color surfaceContainerHigh = Color(0xFFE8E8E8);

  /// Documentation for this public member.
  static const Color surfaceContainerHighest = Color(0xFFE0E0E0);

  // Semantic Utility
  /// Documentation for this public member.
  static const Color white = Color(0xFFFFFFFF);

  /// Documentation for this public member.
  static const Color black = Color(0xFF000000);

  /// Documentation for this public member.
  static const Color transparent = Color(0x00000000);

  /// Documentation for this public member.
  static const Color error = danger;

  /// Documentation for this public member.
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Body text on a navy surface. 7.6:1 on [primaryDark].
  static const Color onPrimarySoft = Color(0xFFE4EBF5);

  /// Secondary text on a navy surface. Replaces the Tailwind slate
  /// (`#94A3B8`, `#E2E8F0`) the responder dashboard carried over from an
  /// older console.
  static const Color onPrimaryMuted = Color(0xFFAFC0D8);

  // Missing semantic tokens
  /// Documentation for this public member.
  static const Color secondary = Color(0xFFB99123);

  /// Documentation for this public member.
  static const Color onSurfaceVariant = Color(0xFF616161);

  // Tactical Aliases
  /// Documentation for this public member.
  static const Color emergency = danger;

  /// Documentation for this public member.
  static const BoxBorder glassBorder = hudBorder;

  /// Documentation for this public member.
  static const Color white05 = Color(0x0D000000); // Dark tint for light HUD
  /// Documentation for this public member.
  static const Color accent = secondary;

  /// Documentation for this public member.
  static const Color safe = success;

  /// Documentation for this public member.

  static BoxDecoration glassSurface = BoxDecoration(
    color: const Color(0x0A000000), // Subtly dark tint for light background
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0x1A000000)),
  );
}
