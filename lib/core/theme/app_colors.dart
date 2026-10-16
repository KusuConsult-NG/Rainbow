import 'package:flutter/material.dart';

/// Plateau Eye brand colour palette — Oxford Navy, Highland Emerald, and Warm Gold
class AppColors {
  AppColors._();

  // Core Palette (Plateau Eye: Oxford Navy, Highland Emerald, Warm Gold)
  /// Background
  static const Color background = Color(0xFFFAFAF7); // Crisp Warm White
  /// Surface
  static const Color surface = Color(0xFFFFFFFF); // Pure White
  /// Surface Light
  static const Color surfaceLight = Color(0xFFF4F5F0);

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

  // Status Palette
  /// Emergency / Critical Alert
  static const Color danger = Color(0xFFD32F2F); // Emergency Red

  /// Warning
  static const Color warning = Color(0xFFFF9800);

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
  static const Color error = Color(0xFFD32F2F);

  /// Documentation for this public member.
  static const Color onPrimary = Color(0xFFFFFFFF);

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
