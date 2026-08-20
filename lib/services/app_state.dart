import 'package:flutter/foundation.dart';

import '../models/nutrition_summary.dart';
import '../models/reviewed_meal.dart';
import '../models/user_profile.dart';
import 'nutrition_calculator.dart';

/// In-memory state that is not worth storing: the profile the user typed in
/// and the meal they are part-way through reviewing.
///
/// Saved meals live in Firestore and are read through `MealRepository`, not
/// from here.
///
/// It is a [ChangeNotifier], so any widget that reads it through `AppScope.of`
/// rebuilds automatically when this state changes.
class AppState extends ChangeNotifier {
  UserProfile? _profile;

  /// Null until the user finishes the profile setup screen.
  UserProfile? get profile => _profile;

  bool get hasProfile => _profile != null;

  /// Daily goals derived from the profile (falls back to sensible defaults).
  NutritionSummary get dailyTargets => NutritionCalculator.targetsFor(_profile);

  /// Stores the profile created in setup, or an edited version of it.
  void saveProfile(UserProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  /// Forgets the profile held in memory.
  ///
  /// Used when the session changes to a different account, so one user's
  /// details are never shown to another. Nothing stored is deleted.
  void clearProfile() {
    if (_profile == null) return;
    _profile = null;
    notifyListeners();
  }

  ReviewedMeal? _pendingMeal;

  /// The meal the user has reviewed and is ready to save, or null.
  ///
  /// Held in memory only. A later phase writes this to storage and turns it
  /// into a [FoodEntry] in the history; for now it is the hand-off point
  /// between reviewing a scan and saving it.
  ReviewedMeal? get pendingMeal => _pendingMeal;

  void setPendingMeal(ReviewedMeal meal) {
    _pendingMeal = meal;
    notifyListeners();
  }

  void clearPendingMeal() {
    if (_pendingMeal == null) return;
    _pendingMeal = null;
    notifyListeners();
  }

  /// Drops everything held for the account that is signing out.
  ///
  /// Every field here belongs to one account, so all of it has to go at once:
  /// the next person to sign in must never see a trace of the last one. One
  /// notification covers the lot, so listeners cannot observe a half-cleared
  /// state where the profile has gone but the meal under review has not.
  ///
  /// Nothing stored is deleted - this only forgets what was in memory.
  void clearForSignOut() {
    if (_profile == null && _pendingMeal == null) return;
    _profile = null;
    _pendingMeal = null;
    notifyListeners();
  }
}
