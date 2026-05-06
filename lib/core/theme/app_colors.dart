import 'package:flutter/material.dart';

/// Operation Rainbow brand colour palette — Tactical Dark Theme
class AppColors {
  AppColors._();

  // Core Tactical Palette
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFF1A1A1A);
  static const Color primary = Color(0xFFAF101A); // Original Brand Red
  static const Color primaryDark = Color(0xFF8B0E15);
  static const Color accent = Color(0xFFAF101A);
  
  // Incident Status Colors
  static const Color emergency = Color(0xFFAF101A);
  static const Color warning = Color(0xFFFFC400);
  static const Color safe = Color(0xFF00C853);
  static const Color inactive = Color(0xFF333333);

  // Text Palette
  static const Color onBackground = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textDim = Color(0xFF666666);

  // Glassmorphic Elements
  static BoxBorder get glassBorder => Border.all(
    color: const Color(0x1AFFFFFF),
    width: 1,
  );
  static Decoration get glassSurface => BoxDecoration(
    color: const Color(0x0DFFFFFF),
    borderRadius: BorderRadius.circular(24),
    border: glassBorder,
  );

  // Legacy Compatibility (Mapping to Dark Theme)
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF4D0000);
  static const Color onPrimaryContainer = Color(0xFFAF101A);
  
  static const Color secondary = Color(0xFF8B0E15); // Darker Brand Red
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFF4D0000);
  static const Color onSecondaryContainer = Color(0xFFAF101A);
  
  static const Color tertiary = Color(0xFF4D0000); // Deep Maroon
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF1A0000);
  static const Color onTertiaryContainer = Color(0xFFAF101A);
  
  static const Color error = Color(0xFFAF101A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFF4D0000);
  static const Color onErrorContainer = Color(0xFFAF101A);

  // Surface Containers
  static const Color surfaceContainerLowest = Color(0xFF0A0A0A);
  static const Color surfaceContainerLow = Color(0xFF121212);
  static const Color surfaceContainer = Color(0xFF1A1A1A);
  static const Color surfaceContainerHigh = Color(0xFF242424);
  static const Color surfaceContainerHighest = Color(0xFF2C2C2C);

  // Surface Variants and Outlines
  static const Color surfaceVariant = Color(0xFF2C2C2C);
  static const Color onSurfaceVariant = Color(0xFFAAAAAA);
  static const Color outline = Color(0xFF444444);
  static const Color outlineVariant = Color(0xFF333333);

  // Misc
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);
  
  static const Color tertiaryFixed = Color(0xFFAF101A);
  static const Color white05 = Color(0x0DFFFFFF);
}

