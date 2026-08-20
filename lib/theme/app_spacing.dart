import 'package:flutter/widgets.dart';

/// Spacing and corner-radius tokens.
///
/// Using a fixed scale (instead of random numbers like 13 or 17) is what makes
/// the layout feel consistent from screen to screen.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Default left/right padding for full screens.
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: lg);

  /// Padding used inside rounded cards.
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

/// Corner radius tokens. NutriScan uses generously rounded cards.
class AppRadius {
  const AppRadius._();

  static const double sm = 10;
  static const double md = 16;
  static const double lg = 20;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius fieldRadius = BorderRadius.all(Radius.circular(md));
}
