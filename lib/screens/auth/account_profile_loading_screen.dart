import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Loads the profile belonging to a user who has just authenticated.
///
/// The previous navigation stack and account-scoped app state are removed
/// before this screen is shown. It therefore never guesses a destination or
/// returns to old account content when Firestore is temporarily unavailable.
class AccountProfileLoadingScreen extends StatefulWidget {
  const AccountProfileLoadingScreen({super.key, required this.expectedUserId});

  /// The Firebase user established by the immediately preceding sign-in.
  final String expectedUserId;

  @override
  State<AccountProfileLoadingScreen> createState() =>
      _AccountProfileLoadingScreenState();
}

class _AccountProfileLoadingScreenState
    extends State<AccountProfileLoadingScreen> {
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    if (!mounted || _isLoading) return;

    final ServicesScope services = ServicesScope.of(context);
    final AuthService auth = services.authService;
    final ProfileRepository profiles = services.profileRepository;
    final appState = AppScope.of(context);

    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (auth.currentUserId != widget.expectedUserId) {
      _showError(
        'Your signed-in session changed before the account could be loaded. '
        'Please try again.',
      );
      return;
    }

    UserProfile? profile;
    try {
      profile = await profiles.getProfile();
    } on ProfileRepositoryFailure catch (failure) {
      if (!mounted) return;
      _showError(failure.message);
      return;
    }

    if (!mounted) return;
    if (auth.currentUserId != widget.expectedUserId) {
      _showError(
        'Your signed-in session changed before the account could be loaded. '
        'Please try again.',
      );
      return;
    }

    if (profile != null) {
      appState.saveProfile(profile);
    } else {
      // The state was already cleared at the authentication boundary. Keep it
      // empty when this account has not created a profile yet.
      appState.clearProfile();
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      profile != null ? AppRoutes.home : AppRoutes.profileSetup,
      (Route<dynamic> route) => false,
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Signed in')));
  }

  void _showError(String message) {
    setState(() {
      _isLoading = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _error == null
                        ? 'Loading your account'
                        : 'Could not load your account',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_error == null) ...<Widget>[
                    Text(
                      'Your profile is being loaded securely.',
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const CircularProgressIndicator(),
                  ] else ...<Widget>[
                    Text(
                      _error!,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: _isLoading ? null : _loadProfile,
                      child: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
