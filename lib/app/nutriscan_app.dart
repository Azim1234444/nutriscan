import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/meal_repository.dart';
import '../services/profile_repository.dart';
import '../theme/app_theme.dart';
import 'app_routes.dart';
import 'app_scope.dart';
import 'services_scope.dart';

/// Root widget: owns the shared services and state, and configures theme and
/// navigation.
class NutriScanApp extends StatefulWidget {
  const NutriScanApp({
    super.key,
    this.authService,
    this.mealRepository,
    this.profileRepository,
  });

  /// Overridable so tests can supply fakes instead of Firebase.
  final AuthService? authService;
  final MealRepository? mealRepository;
  final ProfileRepository? profileRepository;

  @override
  State<NutriScanApp> createState() => _NutriScanAppState();
}

class _NutriScanAppState extends State<NutriScanApp> {
  late final AppState _appState;
  late final AuthService _authService;
  late final MealRepository _mealRepository;
  late final ProfileRepository _profileRepository;

  @override
  void initState() {
    super.initState();

    _appState = AppState();
    _authService = widget.authService ?? FirebaseAuthService();
    _mealRepository =
        widget.mealRepository ??
        FirestoreMealRepository(authService: _authService);
    _profileRepository =
        widget.profileRepository ??
        FirestoreProfileRepository(authService: _authService);
  }

  // No sign-in happens here on purpose. Creating an anonymous account at
  // launch would take the choice away from someone who already has a
  // permanent account and only wants to sign back in to it. A session is
  // established when the app actually needs one: `ensureSignedIn` runs the
  // first time a repository reads or writes - which for a new user is when
  // they save their profile - and signing in recovers an existing account
  // instead.

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      authService: _authService,
      mealRepository: _mealRepository,
      profileRepository: _profileRepository,
      child: AppScope(
        state: _appState,
        child: MaterialApp(
          title: 'NutriScan',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          themeMode: ThemeMode.light,
          initialRoute: AppRoutes.splash,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
  }
}
