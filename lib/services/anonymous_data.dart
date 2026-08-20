import 'app_state.dart';
import 'auth_service.dart';
import 'meal_repository.dart';

/// What a temporary account would leave behind if it were swapped for
/// another one.
///
/// A temporary (anonymous) account is tied to this install, so its documents
/// stay under its own id forever. Nothing is ever lost, but without an email
/// there is no way back to it - which only matters if there is something
/// there in the first place. This is that judgement, kept in one place so the
/// screens and the tests agree on what "has data" means.
class AnonymousData {
  const AnonymousData({required this.hasProfile, required this.hasMeals});

  /// Nothing saved at all - a session and no more.
  static const AnonymousData none = AnonymousData(
    hasProfile: false,
    hasMeals: false,
  );

  final bool hasProfile;
  final bool hasMeals;

  /// Whether losing track of this account would actually cost the user
  /// something.
  ///
  /// Simply being signed in anonymously does not count: a brand new user with
  /// an empty account has nothing to protect and should not be warned.
  bool get isWorthKeeping => hasProfile || hasMeals;
}

/// Works out what the current session has saved.
///
/// Answers [AnonymousData.none] for anybody who is not on a temporary
/// account, so callers can ask unconditionally. The profile comes from state
/// already in memory and the meal check reads one document at most, so this
/// is cheap enough to call when a button is pressed.
Future<AnonymousData> readAnonymousData({
  required AuthService auth,
  required AppState appState,
  required MealRepository meals,
}) async {
  // Only a temporary account can be stranded; a permanent one is reachable
  // again through its email, and no session has nothing to strand.
  if (auth.isAnonymous != true) return AnonymousData.none;

  return AnonymousData(
    hasProfile: appState.hasProfile,
    hasMeals: await meals.hasAnyMeals(),
  );
}
