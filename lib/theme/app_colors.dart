import 'package:flutter/material.dart';

/// Central colour tokens for NutriScan.
///
/// Widgets should read colours from here (or from `Theme.of(context)`) instead
/// of hard-coding hex values, so the whole app can be restyled from one file.
class AppColors {
  // This class only holds constants, so it is never instantiated.
  const AppColors._();

  // --- Brand ---------------------------------------------------------------

  /// Main nutrition green. Used for primary buttons and the calorie ring.
  static const Color primary = Color(0xFF1B8A5A);

  /// Darker green for text on light green surfaces.
  static const Color primaryDark = Color(0xFF0E5C3A);

  /// Very light green used as a card / chip background.
  static const Color primarySoft = Color(0xFFE4F3EB);

  // --- Neutrals ------------------------------------------------------------

  /// App background behind cards.
  static const Color background = Color(0xFFF5F7F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFE1E7E4);

  /// Headline / body text. Contrast ratio > 12:1 on [surface].
  static const Color textPrimary = Color(0xFF12211B);

  /// Supporting text. Contrast ratio > 4.5:1 on [surface].
  static const Color textSecondary = Color(0xFF57665F);

  // --- Macro nutrients -----------------------------------------------------
  // Each macro keeps the same colour everywhere in the app so users can
  // recognise it at a glance.

  static const Color protein = Color(0xFF2563EB);
  static const Color proteinSoft = Color(0xFFE8EFFE);

  static const Color carbs = Color(0xFFB45309);
  static const Color carbsSoft = Color(0xFFFDF0DF);

  static const Color fat = Color(0xFF7C3AED);
  static const Color fatSoft = Color(0xFFF1EAFE);

  // --- Feedback ------------------------------------------------------------

  static const Color danger = Color(0xFFB3261E);
}
