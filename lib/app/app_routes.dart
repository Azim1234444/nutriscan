import 'package:flutter/material.dart';

import '../models/food_analysis_result.dart';
import '../models/saved_meal.dart';
import '../models/user_profile.dart';
import '../screens/auth/create_account_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/history/edit_meal_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/profile_setup/profile_setup_screen.dart';
import '../screens/result/analysis_result_screen.dart';
import '../screens/result/edit_nutrition_screen.dart';
import '../screens/splash/splash_screen.dart';
import 'main_shell.dart';

/// All named routes in one place.
///
/// Named routes keep navigation simple for an app this size: screens only need
/// `Navigator.pushNamed(context, AppRoutes.something)` and never import each
/// other.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String profileSetup = '/profile-setup';

  /// The tabbed part of the app (home, scan, history, profile).
  static const String home = '/home';

  /// AI nutrition estimate for one photo. Takes [AnalysisResultArgs].
  static const String analysisResult = '/analysis-result';

  /// Upgrades the anonymous account to a permanent one. Pops with true when
  /// the account was created.
  static const String createAccount = '/create-account';

  /// Signs in to an account that already exists, recovering its user id.
  static const String signIn = '/sign-in';

  /// Asks Firebase to email a password reset link. Takes an optional String
  /// to prefill the address.
  static const String resetPassword = '/reset-password';

  /// Form for correcting an estimate. Takes a [FoodAnalysisResult] and pops
  /// with the edited copy, or with null when cancelled.
  static const String editNutrition = '/edit-nutrition';

  /// Form for correcting a meal already in history. Takes a [SavedMeal] and
  /// pops with true once the change is stored.
  static const String editMeal = '/edit-meal';

  /// Builds the route for a name. Passed to `MaterialApp.onGenerateRoute`.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _page(const SplashScreen(), settings);

      case onboarding:
        return _page(const OnboardingScreen(), settings);

      case profileSetup:
        // A UserProfile argument means "edit this profile"; null means
        // "create a new one".
        final Object? argument = settings.arguments;
        return _page(
          ProfileSetupScreen(
            existingProfile: argument is UserProfile ? argument : null,
          ),
          settings,
        );

      case home:
        return _page(const MainShell(), settings);

      case analysisResult:
        final Object? argument = settings.arguments;
        if (argument is! AnalysisResultArgs) {
          return _page(
            const _UnknownRouteScreen(routeName: analysisResult),
            settings,
          );
        }
        return _page(AnalysisResultScreen(args: argument), settings);

      case createAccount:
        return _page<bool>(const CreateAccountScreen(), settings);

      case signIn:
        return _page(const SignInScreen(), settings);

      case resetPassword:
        final Object? argument = settings.arguments;
        return _page(
          ResetPasswordScreen(
            initialEmail: argument is String ? argument : null,
          ),
          settings,
        );

      case editMeal:
        final Object? meal = settings.arguments;
        if (meal is! SavedMeal) {
          return _page<bool>(
            const _UnknownRouteScreen(routeName: editMeal),
            settings,
          );
        }
        return _page<bool>(EditMealScreen(meal: meal), settings);

      case editNutrition:
        final Object? current = settings.arguments;
        if (current is! FoodAnalysisResult) {
          return _page<FoodAnalysisResult?>(
            const _UnknownRouteScreen(routeName: editNutrition),
            settings,
          );
        }
        return _page<FoodAnalysisResult?>(
          EditNutritionScreen(result: current),
          settings,
        );

      default:
        return _page(_UnknownRouteScreen(routeName: settings.name), settings);
    }
  }

  /// Builds a route that returns [T] when it pops.
  ///
  /// The type argument matters: `Navigator.pushNamed<T>` casts the route to
  /// `Route<T?>`, so a screen that pops with a value - the nutrition editor -
  /// needs its result type here, not `dynamic`.
  static MaterialPageRoute<T> _page<T>(Widget child, RouteSettings settings) {
    return MaterialPageRoute<T>(
      builder: (BuildContext context) => child,
      settings: settings,
    );
  }
}

/// Safety net so a typo in a route name shows a readable screen instead of a
/// crash.
class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(child: Text('No screen is registered for "$routeName".')),
    );
  }
}
