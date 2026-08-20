import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// First screen the user sees.
///
/// While the brand is showing it looks for an existing session and its stored
/// profile, then sends the user to the dashboard if they have one, or to
/// onboarding if they do not. A returning user never sees onboarding again.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Keeps the brand on screen for a moment even if loading is instant.
  static const Duration _minimumDisplay = Duration(seconds: 2);

  /// Set when the profile could not be loaded, so the user can retry.
  String? _error;

  @override
  void initState() {
    super.initState();
    // The frame has to be built before ServicesScope can be read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// Picks up any existing session, loads its profile, then routes.
  Future<void> _start() async {
    final ProfileRepository profiles = ServicesScope.of(context)
        .profileRepository;
    final AuthService auth = ServicesScope.of(context).authService;
    final appState = AppScope.of(context);

    setState(() => _error = null);
    final Future<void> minimumWait = Future<void>.delayed(_minimumDisplay);

    // Nobody is signed in - a first run, a new device, or cleared storage.
    // There is nothing stored to load, and signing in anonymously here would
    // quietly rule out recovering an existing account, so onboarding takes
    // over: it can start a fresh anonymous session or hand over to sign-in.
    if (auth.currentUserId == null) {
      await minimumWait;
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
      return;
    }

    UserProfile? profile;
    try {
      profile = await profiles.getProfile();
    } on ProfileRepositoryFailure catch (failure) {
      await minimumWait;
      if (!mounted) return;
      setState(() => _error = failure.message);
      return;
    }

    // A stored profile goes straight into app state, so every screen sees it.
    if (profile != null) appState.saveProfile(profile);

    await minimumWait;
    if (!mounted) return;

    Navigator.of(context).pushReplacementNamed(
      profile != null ? AppRoutes.home : AppRoutes.onboarding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                height: 96,
                width: 96,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  size: 52,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'NutriScan',
                style: text.displaySmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Scan your food. Know your nutrition.',
                style: text.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (_error == null)
                SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                )
              else
                _StartupError(message: _error!, onRetry: _start),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the profile could not be loaded at startup.
///
/// The app cannot decide where to send the user without knowing whether they
/// have a profile, so it says what went wrong and offers another go rather
/// than guessing.
class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Text(
            message,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size(160, 48),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
