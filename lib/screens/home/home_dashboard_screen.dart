import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/services_scope.dart';
import '../../models/food_entry.dart';
import '../../models/macro.dart';
import '../../models/nutrition_summary.dart';
import '../../models/saved_meal.dart';
import '../../models/user_profile.dart';
import '../../services/app_state.dart';
import '../../services/meal_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/week.dart';
import '../../widgets/app_card.dart';
import '../../widgets/calorie_summary_card.dart';
import '../../widgets/macro_stat_card.dart';
import '../../widgets/meal_tile.dart';
import '../../widgets/section_header.dart';

/// The Home tab: today's totals, the scan action and the latest meals.
///
/// Reads two streams rather than one, because the two halves of the screen
/// want different things. Today's totals need every meal logged today and
/// nothing else; the recent list needs the newest few whenever they were
/// eaten. One query cannot be both without either reading the whole history
/// or risking a day that does not add up.
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    required this.onScanPressed,
    required this.onSeeAllMealsPressed,
    this.clock = DateTime.now,
  });

  /// Opens the Scan tab.
  final VoidCallback onScanPressed;

  /// Opens the History tab.
  final VoidCallback onSeeAllMealsPressed;

  /// Reads the current time.
  ///
  /// Only ever replaced by tests, which need to move the clock past midnight
  /// to check the day the totals are for. Production passes nothing and gets
  /// the real one.
  final DateTime Function() clock;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  /// The repository the two streams come from.
  late MealRepository _repository;

  /// Every meal logged on [_day], which is what the totals add up.
  Stream<List<SavedMeal>>? _todayMeals;

  /// The newest few meals from the whole history, for the preview list.
  Stream<List<SavedMeal>>? _recentMeals;

  /// The day [_todayMeals] was opened for.
  ///
  /// Held so the stream can be reopened when the day underneath it changes,
  /// and only then. The shell rebuilds this screen on every tab change, so
  /// the alternative - working the day out in `build` - is what used to
  /// throw the streams away several times a minute.
  DateTime? _day;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = ServicesScope.of(context).mealRepository;
    _openStreams();
  }

  /// Opens both streams for today, if they are not already open for it.
  ///
  /// Idempotent on purpose: called from [didChangeDependencies] and again
  /// from `build`, and does nothing at all unless the day has moved on.
  void _openStreams() {
    final DateTime today = Week.dayOf(widget.clock());
    if (_todayMeals != null && _recentMeals != null && _day == today) return;

    _day = today;
    _todayMeals = _repository.watchMealsForDay(today);
    // Not scoped to the day: somebody who has not eaten yet should still see
    // what they ate yesterday.
    _recentMeals ??= _repository.watchRecentMeals();
  }

  /// Reopens both streams after a failure, so the user can try again.
  ///
  /// A new pair of streams is the whole retry: the repository re-reads, and
  /// whatever went wrong - no connection, a refused read - is attempted
  /// again from the beginning.
  void _retry() {
    setState(() {
      _day = null;
      _todayMeals = null;
      _recentMeals = null;
      _openStreams();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Catches the clock rolling past midnight while the app is open. Costs a
    // date comparison per rebuild and reopens nothing unless the day changed.
    _openStreams();

    return StreamBuilder<List<SavedMeal>>(
      stream: _todayMeals,
      builder:
          (BuildContext context, AsyncSnapshot<List<SavedMeal>> todaySnapshot) {
            return StreamBuilder<List<SavedMeal>>(
              stream: _recentMeals,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<SavedMeal>> recentSnapshot,
                  ) {
                    // A read that failed is not a day with nothing in it.
                    // Saying "0 kcal" here would be inventing a fact about
                    // what somebody ate, so the numbers are withheld and the
                    // trouble is named instead.
                    final bool failed =
                        todaySnapshot.hasError || recentSnapshot.hasError;

                    return _Dashboard(
                      todayMeals:
                          todaySnapshot.data ?? const <SavedMeal>[],
                      recentMeals:
                          recentSnapshot.data ?? const <SavedMeal>[],
                      failed: failed,
                      onRetry: _retry,
                      onScanPressed: widget.onScanPressed,
                      onSeeAllMealsPressed: widget.onSeeAllMealsPressed,
                    );
                  },
            );
          },
    );
  }
}

/// The dashboard itself, once the meals are known.
class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.todayMeals,
    required this.recentMeals,
    required this.failed,
    required this.onRetry,
    required this.onScanPressed,
    required this.onSeeAllMealsPressed,
  });

  /// Every meal logged today, which is what the totals add up.
  final List<SavedMeal> todayMeals;

  /// The newest meals from the whole history, already limited by the query.
  final List<SavedMeal> recentMeals;

  /// True when either read failed, so no number here can be trusted.
  final bool failed;

  final VoidCallback onRetry;
  final VoidCallback onScanPressed;
  final VoidCallback onSeeAllMealsPressed;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final UserProfile? profile = state.profile;
    final NutritionSummary targets = state.dailyTargets;

    // Today's totals use the user's reviewed values, counting each meal once.
    // The list is already the day's, so there is no day filter here.
    final NutritionSummary consumed = totalsFor(todayMeals);
    final List<FoodEntry> recent = recentMeals
        .map((SavedMeal meal) => meal.toFoodEntry())
        .toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            _DashboardHeader(profile: profile),
            const SizedBox(height: AppSpacing.lg),

            // The targets and the scan button work without the meals, so the
            // screen stays useful; only the parts that would have to state a
            // number are held back.
            if (failed) ...<Widget>[
              _MealsUnavailableCard(onRetry: onRetry),
              const SizedBox(height: AppSpacing.lg),
            ] else ...<Widget>[
              CalorieSummaryCard(consumed: consumed, target: targets),
              const SizedBox(height: AppSpacing.md),

              _MacroRow(consumed: consumed, targets: targets),
              const SizedBox(height: AppSpacing.lg),
            ],

            FilledButton.icon(
              onPressed: onScanPressed,
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Scan Food'),
            ),

            if (!failed) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),

              SectionHeader(
                title: 'Recent meals',
                actionLabel: 'See all',
                onActionPressed: onSeeAllMealsPressed,
              ),
              const SizedBox(height: AppSpacing.sm),

              if (recent.isEmpty)
                const _NoMealsCard()
              else
                for (final FoodEntry entry in recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: MealTile(entry: entry),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Greeting line with the user's initials on the right.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.profile});

  final UserProfile? profile;

  String get _greeting {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String name = profile?.name ?? 'there';

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$_greeting,', style: text.bodyMedium),
              const SizedBox(height: 2),
              Text(
                name,
                style: text.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          height: 48,
          width: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            profile?.initials ?? 'N',
            style: text.titleMedium?.copyWith(color: AppColors.primaryDark),
          ),
        ),
      ],
    );
  }
}

/// Protein / carbs / fat cards side by side.
class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.consumed, required this.targets});

  final NutritionSummary consumed;
  final NutritionSummary targets;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight gives the row a real height, so `stretch` can make all
    // three cards as tall as the tallest one instead of asking for infinity.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final Macro macro in Macro.values) ...<Widget>[
            Expanded(
              child: MacroStatCard(
                macro: macro,
                consumedG: macro.valueIn(consumed),
                targetG: macro.valueIn(targets),
              ),
            ),
            if (macro != Macro.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Shown when the meals could not be read at all.
///
/// Deliberately in place of the totals rather than alongside them. A day
/// whose meals could not be loaded is not a day of nothing, and showing
/// "0 kcal" next to a warning would still leave the wrong number on screen
/// for somebody to act on.
///
/// The wording is the app's own. Firebase's message and code stay out of it -
/// neither means anything to the person reading this, and the code can name
/// internals.
class _MealsUnavailableCard extends StatelessWidget {
  const _MealsUnavailableCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Today's meals could not be loaded", style: text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Check your connection and try again. Nothing you have '
                  'saved has been lost.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on the dashboard when nothing has been logged yet.
class _NoMealsCard extends StatelessWidget {
  const _NoMealsCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        children: <Widget>[
          const Icon(Icons.restaurant_outlined, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'No meals logged yet. Scan your first meal to see it here.',
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
