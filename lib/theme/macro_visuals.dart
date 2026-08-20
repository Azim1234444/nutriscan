import 'package:flutter/material.dart';

import '../models/macro.dart';
import 'app_colors.dart';

/// Maps each macronutrient to its colour and icon.
///
/// Protein is always blue, carbs always amber, fat always purple - on every
/// screen - which is what makes the numbers readable at a glance.
class MacroVisuals {
  const MacroVisuals._();

  static Color color(Macro macro) {
    switch (macro) {
      case Macro.protein:
        return AppColors.protein;
      case Macro.carbs:
        return AppColors.carbs;
      case Macro.fat:
        return AppColors.fat;
    }
  }

  /// Tinted background that pairs with [color].
  static Color softColor(Macro macro) {
    switch (macro) {
      case Macro.protein:
        return AppColors.proteinSoft;
      case Macro.carbs:
        return AppColors.carbsSoft;
      case Macro.fat:
        return AppColors.fatSoft;
    }
  }

  static IconData icon(Macro macro) {
    switch (macro) {
      case Macro.protein:
        return Icons.egg_alt_outlined;
      case Macro.carbs:
        return Icons.bakery_dining_outlined;
      case Macro.fat:
        return Icons.water_drop_outlined;
    }
  }
}
