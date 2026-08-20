import 'package:flutter/material.dart';

import '../../app/services_scope.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/labeled_field.dart';
import 'create_account_screen.dart' show looksLikeEmail;

/// Asks Firebase to email a password reset link.
///
/// The app deliberately does no more than this: the new password is chosen on
/// Firebase's own page, so it never passes through NutriScan and there is
/// nothing here to store or leak.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail});

  /// Address carried over from the sign-in form, so it need not be retyped.
  final String? initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );

  bool _isSending = false;
  bool _isSent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address';
    if (!looksLikeEmail(email)) return 'Enter a valid email address';
    return null;
  }

  Future<void> _sendResetEmail() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_isSending) return;

    final AuthService auth = ServicesScope.of(context).authService;

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      await auth.sendPasswordResetEmail(_emailController.text);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = failure.message;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _isSent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
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
              Text('Forgot your password?', style: text.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Enter the email address on your account and we will send a '
                'link for choosing a new password.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),

              LabeledField(
                label: 'Email',
                child: TextFormField(
                  controller: _emailController,
                  validator: _validateEmail,
                  enabled: !_isSent,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                  ),
                ),
              ),

              if (_isSent) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                const _ResetNoticeCard(
                  icon: Icons.mark_email_read_outlined,
                  color: AppColors.primary,
                  title: 'Check your inbox',
                  // Worded the same whether or not an account exists, so this
                  // screen cannot be used to find out who has one.
                  message:
                      'If that address has a NutriScan account, a reset link '
                      'is on its way. Follow it to choose a new password, then '
                      'come back and sign in.',
                ),
              ],

              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _ResetNoticeCard(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.textSecondary,
                  title: 'Email not sent',
                  message: _error!,
                ),
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
            child: _isSent
                ? FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to sign in'),
                  )
                : FilledButton(
                    onPressed: _isSending ? null : _sendResetEmail,
                    child: _isSending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _error != null ? 'Try again' : 'Send reset email',
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// One card used for both the sent confirmation and a failure.
class _ResetNoticeCard extends StatelessWidget {
  const _ResetNoticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.titleMedium),
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
