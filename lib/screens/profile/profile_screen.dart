import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../models/macro.dart';
import '../../models/nutrition_summary.dart';
import '../../models/user_profile.dart';
import '../../services/app_state.dart';
import '../../services/anonymous_data.dart';
import '../../services/auth_service.dart';
import '../auth/anonymous_rescue_dialog.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/macro_visuals.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/info_row.dart';
import '../../widgets/section_header.dart';

/// The Profile tab: shows the saved details and opens the edit form.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _openEditor(BuildContext context, UserProfile? profile) {
    Navigator.of(context).pushNamed(AppRoutes.profileSetup, arguments: profile);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final UserProfile? profile = state.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: <Widget>[
          if (profile != null)
            IconButton(
              onPressed: () => _openEditor(context, profile),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
            ),
        ],
      ),
      body: SafeArea(
        child: profile == null
            ? EmptyState(
                icon: Icons.person_outline_rounded,
                title: 'No profile yet',
                message:
                    'Add your details so NutriScan can calculate your daily '
                    'calorie and macro targets.',
                actionLabel: 'Set up profile',
                onActionPressed: () => _openEditor(context, null),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: <Widget>[
                  _ProfileHeaderCard(profile: profile),
                  const SizedBox(height: AppSpacing.lg),

                  const SectionHeader(title: 'Your details'),
                  const SizedBox(height: AppSpacing.sm),
                  _DetailsCard(profile: profile),
                  const SizedBox(height: AppSpacing.lg),

                  const SectionHeader(title: 'Daily targets'),
                  const SizedBox(height: AppSpacing.sm),
                  _TargetsCard(targets: state.dailyTargets),
                  const SizedBox(height: AppSpacing.lg),

                  const SectionHeader(title: 'Account'),
                  const SizedBox(height: AppSpacing.sm),
                  const _AccountSection(),
                  const SizedBox(height: AppSpacing.lg),

                  OutlinedButton.icon(
                    onPressed: () => _openEditor(context, profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Avatar, name, goal and BMI.
class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            height: 64,
            width: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              profile.initials,
              style: text.headlineSmall?.copyWith(color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  profile.name,
                  style: text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(profile.goal.label, style: text.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'BMI ${profile.bmi.toStringAsFixed(1)} · '
                    '${profile.bmiCategory}',
                    style: text.bodySmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The raw profile fields, one per row.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: <Widget>[
          InfoRow(
            icon: Icons.cake_outlined,
            label: 'Age',
            value: '${profile.age} years',
          ),
          const Divider(),
          InfoRow(
            icon: Icons.wc_outlined,
            label: 'Gender',
            value: profile.gender.label,
          ),
          const Divider(),
          InfoRow(
            icon: Icons.straighten_outlined,
            label: 'Height',
            value: '${Formatters.measurement(profile.heightCm)} cm',
          ),
          const Divider(),
          InfoRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight',
            value: '${Formatters.measurement(profile.weightKg)} kg',
          ),
          const Divider(),
          InfoRow(
            icon: Icons.directions_run_outlined,
            label: 'Activity level',
            value: profile.activityLevel.label,
          ),
          const Divider(),
          InfoRow(
            icon: Icons.flag_outlined,
            label: 'Goal',
            value: profile.goal.label,
          ),
        ],
      ),
    );
  }
}

/// Calorie and macro goals calculated from the profile.
class _TargetsCard extends StatelessWidget {
  const _TargetsCard({required this.targets});

  final NutritionSummary targets;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Daily calories', style: text.bodyLarge)),
              Text(
                '${Formatters.calories(targets.calories)} kcal',
                style: text.titleMedium?.copyWith(color: AppColors.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          for (final Macro macro in Macro.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  Container(
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(
                      color: MacroVisuals.color(macro),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(macro.label, style: text.bodyLarge)),
                  Text(
                    Formatters.grams(macro.valueIn(targets)),
                    style: text.titleSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Offers the account upgrade, or confirms it is already done.
///
/// Kept as its own stateful widget so it can refresh after the create-account
/// screen returns, without the profile screen needing to know about auth.
class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  /// True while the sign-out request is in flight.
  bool _isSigningOut = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AuthService auth = ServicesScope.of(context).authService;
    final bool? isAnonymous = auth.isAnonymous;

    // Nothing to show until the session is known.
    if (isAnonymous == null) return const SizedBox.shrink();

    if (!isAnonymous) {
      final String? email = auth.currentUserEmail;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppCard(
            color: AppColors.primarySoft,
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Account secured',
                        style: text.titleMedium?.copyWith(
                          color: AppColors.primaryDark,
                        ),
                      ),
                      // The email says which account this is. The user id is
                      // deliberately not shown.
                      if (email != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          email,
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Your meals and profile are tied to your email, so '
                        'they follow you to a new device.',
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SignOutButton(
            isSigningOut: _isSigningOut,
            onPressed: () => _confirmSignOut(isAnonymous: false),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Create an account', style: text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Create an account to keep your meals and profile when you '
                'change devices.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _openCreateAccount,
                icon: const Icon(Icons.person_add_alt_outlined),
                label: const Text('Create Account'),
              ),
              const SizedBox(height: AppSpacing.xs),
              // For someone whose account is on another device: signing in
              // swaps the session, so it is offered quietly under the main
              // action and says plainly what happens to what is on this
              // device.
              TextButton(
                onPressed: _openSignIn,
                child: const Text('Already have an account? Sign in'),
              ),
              Text(
                'Signing in switches to that account. Anything saved on this '
                'device stays with the account it was saved under.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SignOutButton(
          isSigningOut: _isSigningOut,
          onPressed: () => _confirmSignOut(isAnonymous: true),
        ),
      ],
    );
  }

  /// Opens the upgrade form and refreshes once it reports success.
  Future<void> _openCreateAccount() async {
    final bool? created = await Navigator.of(context)
        .pushNamed<bool>(AppRoutes.createAccount);

    if (created == true && mounted) setState(() {});
  }

  /// Opens sign-in, checking first whether anything would be left behind.
  ///
  /// A temporary account with saved data gets the rescue prompt; anybody else
  /// goes straight through, because there is nothing to warn them about.
  Future<void> _openSignIn() async {
    final ServicesScope services = ServicesScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AnonymousData data = await readAnonymousData(
      auth: services.authService,
      appState: AppScope.of(context),
      meals: services.mealRepository,
    );
    if (!mounted) return;

    if (data.isWorthKeeping) {
      final RescueChoice? choice = await showAnonymousRescueDialog(
        context,
        data: data,
      );
      if (!mounted) return;

      switch (choice) {
        case RescueChoice.createAccount:
          // The Phase 2G upgrade: same account, same id, nothing moves.
          await _openCreateAccount();
          return;
        case RescueChoice.signInAnyway:
          break;
        case RescueChoice.cancel:
        case null:
          return;
      }
    }

    await navigator.pushNamed(AppRoutes.signIn);
    if (mounted) setState(() {});
  }

  /// Asks before ending the session, then ends it.
  ///
  /// Signing out is easy to tap by accident and, for a temporary account,
  /// hard to undo - so it always goes through a dialog that says what will
  /// happen to the data.
  Future<void> _confirmSignOut({required bool isAnonymous}) async {
    if (_isSigningOut) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Sign out?'),
          content: Text(
            isAnonymous
                // Nothing is deleted, but without an email there is no way
                // back to this account, so say so plainly.
                ? "You're using a temporary account. If you sign out before "
                      'creating an account, data saved to this temporary '
                      'account may not be recoverable on this device.'
                : 'Your saved meals and profile will remain safely stored in '
                      'your account.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _signOut();
  }

  Future<void> _signOut() async {
    final AuthService auth = ServicesScope.of(context).authService;
    final AppState appState = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() => _isSigningOut = true);

    try {
      await auth.signOut();
    } on AuthFailure catch (failure) {
      // The session is still live, so stay where we are and say why.
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }

    // Nothing in memory belongs to anybody now. This happens before the
    // navigation so no frame can render the old profile without a session.
    appState.clearForSignOut();

    // The whole stack goes: with no route left underneath, the back gesture
    // cannot return to the account that just signed out.
    navigator.pushNamedAndRemoveUntil(
      AppRoutes.onboarding,
      (Route<dynamic> route) => false,
    );
  }
}

/// The sign-out action, shown for both kinds of account.
class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.isSigningOut, required this.onPressed});

  final bool isSigningOut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isSigningOut ? null : onPressed,
      icon: const Icon(Icons.logout_outlined),
      label: const Text('Sign out'),
    );
  }
}
