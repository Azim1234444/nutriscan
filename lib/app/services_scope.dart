import 'package:flutter/widgets.dart';

import '../services/auth_service.dart';
import '../services/meal_repository.dart';
import '../services/profile_repository.dart';

/// Makes the app's services available to every screen.
///
/// Separate from `AppScope`, which carries changing data: these objects are
/// created once and never replaced, so widgets reading them do not rebuild.
/// Tests provide fakes by wrapping the widget under test in their own scope.
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.authService,
    required this.mealRepository,
    required this.profileRepository,
    required super.child,
  });

  final AuthService authService;
  final MealRepository mealRepository;
  final ProfileRepository profileRepository;

  static ServicesScope of(BuildContext context) {
    final ServicesScope? scope = context
        .dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'No ServicesScope found above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) {
    return authService != oldWidget.authService ||
        mealRepository != oldWidget.mealRepository ||
        profileRepository != oldWidget.profileRepository;
  }
}
