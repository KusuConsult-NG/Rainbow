import 'package:flutter/material.dart';

/// Operation Rainbow brand colour palette — White and Red Theme
class AppColors {
  AppColors._();

  // Core Palette (White and Red)
  /// Documentation for this public member.
  static const Color background = Color(0xFFFFFFFF); // Pure White
  /// Documentation for this public member.
  static const Color surface = Color(0xFFFBFBFB); // Off-white
  /// Documentation for this public member.
  static const Color surfaceLight = Color(0xFFF5F5F5);

  /// Documentation for this public member.
  static const Color primary = Color(0xFFE31E24); // Sharp Vibrant Red
  /// Documentation for this public member.
  static const Color primaryDark = Color(0xFFB0171B);

  // Status Palette
  /// Documentation for this public member.
  static const Color danger = Color(0xFFE31E24);

  /// Documentation for this public member.
  static const Color warning = Color(0xFFFF9800);

  /// Documentation for this public member.
  static const Color success =
      Color(0xFF1B5E20); // Darker Green for better contrast on white
  /// Documentation for this public member.
  static const Color info = Color(0xFF0277BD); // Deep Blue

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
  static const Color secondary = Color(0xFF0277BD);

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
