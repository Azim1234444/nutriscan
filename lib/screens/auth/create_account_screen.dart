import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/services_scope.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_field.dart';

/// A loose check that an address has the shape of an email.
///
/// Written with plain string operations rather than a regular expression: the
/// real check is Firebase accepting the address, so this only has to catch
/// obvious typos.
bool looksLikeEmail(String email) {
  if (email.contains(' ')) return false;

  final int at = email.indexOf('@');
  if (at <= 0 || at != email.lastIndexOf('@')) return false;

  final String domain = email.substring(at + 1);
  final int dot = domain.lastIndexOf('.');
  return dot > 0 && dot < domain.length - 1;
}

/// Turns the current anonymous account into a permanent one.
///
/// The account is linked rather than replaced, so the user keeps the same id
/// and everything they have already saved stays where it is. The password goes
/// straight to Firebase Auth: it is never stored, logged, or held in app state.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  /// Shortest password the app accepts.
  static const int _minimumPasswordLength = 8;

  bool _isSaving = false;
  bool _showPassword = false;
  String? _error;

  /// True when the failed attempt also left the device signed out.
  ///
  /// This changes what the screen is for. Retrying would start a fresh
  /// anonymous account and link the email to that instead, quietly leaving
  /// everything the user had under an id nothing can reach again - so the
  /// form is closed off and the way back in is offered instead.
  bool _sessionLost = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address';
    if (!looksLikeEmail(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Enter a password';
    if (password.length < _minimumPasswordLength) {
      return 'Use at least $_minimumPasswordLength characters';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) return 'Re-enter your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  /// Links the email and password to the account that is already signed in.
  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    final AuthService auth = ServicesScope.of(context).authService;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await auth.linkEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = failure.message;
        // Nothing here is retried when the session went with the attempt.
        _sessionLost = failure is AuthSessionLost;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    navigator.pop(true);
    messenger.showSnackBar(const SnackBar(content: Text('Account created')));
  }

  /// Takes somebody whose session went with the failed attempt back to
  /// sign-in.
  ///
  /// The whole stack goes first: every screen under this one was built for an
  /// account this device no longer has, so none of it should be reachable.
  /// Onboarding sits underneath, which is where a device with no session
  /// belongs and what a back gesture should find.
  Future<void> _goToSignIn() async {
    final NavigatorState navigator = Navigator.of(context);

    navigator.pushNamedAndRemoveUntil(
      AppRoutes.onboarding,
      (Route<dynamic> route) => false,
    );
    await navigator.pushNamed(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
              Text('Keep your data safe', style: text.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your meals and profile are already saved to this device. Add '
                'an email and password to keep them if you change devices.',
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
                helperText: 'At least $_minimumPasswordLength characters.',
                child: TextFormField(
                  controller: _passwordController,
                  validator: _validatePassword,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[AutofillHints.newPassword],
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
              const SizedBox(height: AppSpacing.lg),

              LabeledField(
                label: 'Confirm password',
                child: TextFormField(
                  controller: _confirmController,
                  validator: _validateConfirmation,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),

              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                if (_sessionLost)
                  _SessionLostCard(message: _error!)
                else
                  _ErrorCard(message: _error!),
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
            // With no session there is nothing to link an email to, so the
            // only honest action left is the way back in.
            child: _sessionLost
                ? FilledButton.icon(
                    onPressed: _goToSignIn,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Go to sign in'),
                  )
                : FilledButton(
                    onPressed: _isSaving ? null : _createAccount,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_error != null ? 'Try again' : 'Create account'),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Explains an attempt that took the session with it.
///
/// Deliberately different from [_ErrorCard]: this is not a retryable mistake.
/// It says plainly that nothing was deleted, because the natural fear here is
/// that the data has gone - it has not, it is simply under an account this
/// device is no longer holding.
class _SessionLostCard extends StatelessWidget {
  const _SessionLostCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_reset_rounded, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Signed out', style: text.titleMedium),
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

/// Explains a failed attempt without repeating anything the user typed.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

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
                Text('Account not created', style: text.titleMedium),
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
