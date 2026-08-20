import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../models/user_profile.dart';
import '../../services/app_state.dart';
import '../../services/auth_service.dart';
import '../../services/profile_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_field.dart';
import 'create_account_screen.dart' show looksLikeEmail;

/// Signs in to an account the user already has.
///
/// This is the way back to a NutriScan account on a new device, or after the
/// app's storage has been cleared. Authenticating returns the id the account
/// was created with, so the profile and meals stored under it are simply there
/// again - nothing is copied, moved, or recreated.
///
/// The password goes straight to Firebase Auth. It is never stored, logged, or
/// put into app state.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSigningIn = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address';
    if (!looksLikeEmail(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    return null;
  }

  /// Authenticates, then loads whatever that account already had.
  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    // A second tap while the first request is in flight is ignored, so one
    // attempt can never become two.
    if (_isSigningIn) return;

    final ServicesScope services = ServicesScope.of(context);
    final AuthService auth = services.authService;
    final ProfileRepository profiles = services.profileRepository;
    final AppState appState = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSigningIn = true;
      _error = null;
    });

    UserProfile? profile;
    try {
      await auth.signInWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      // Read the profile of the account just recovered, so the app does not
      // carry the previous session's details into this one.
      profile = await profiles.getProfile();
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSigningIn = false;
        _error = failure.message;
      });
      return;
    } on ProfileRepositoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSigningIn = false;
        _error = failure.message;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (profile != null) {
      appState.saveProfile(profile);
    } else {
      appState.clearProfile();
    }

    // The whole stack is replaced: nothing from the previous session should
    // stay reachable with a back gesture.
    navigator.pushNamedAndRemoveUntil(
      profile != null ? AppRoutes.home : AppRoutes.profileSetup,
      (Route<dynamic> route) => false,
    );
    messenger.showSnackBar(const SnackBar(content: Text('Signed in')));
  }

  Future<void> _openReset() async {
    await Navigator.of(context).pushNamed(
      AppRoutes.resetPassword,
      arguments: _emailController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: <Widget>[
              Text('Welcome back', style: text.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Sign in with the email and password you saved your account '
                'with. Your profile and meals will be waiting.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),

              LabeledField(
                label: 'Email',
                child: TextFormField(
                  controller: _emailController,
                  validator: _validateEmail,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              LabeledField(
                label: 'Password',
                child: TextFormField(
                  controller: _passwordController,
                  validator: _validatePassword,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[AutofillHints.password],
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                    ),
                  ),
                ),
              ),

              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _isSigningIn ? null : _openReset,
                  child: const Text('Forgot password?'),
                ),
              ),

              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _SignInErrorCard(message: _error!),
              ],
            ],
          ),
        ),
      ),
      // The keyboard would cover a bottom bar, so its height is added here.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.lg),
            child: FilledButton(
              onPressed: _isSigningIn ? null : _signIn,
              child: _isSigningIn
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_error != null ? 'Try again' : 'Sign in'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains a failed attempt without repeating anything the user typed.
class _SignInErrorCard extends StatelessWidget {
  const _SignInErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Not signed in', style: text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
