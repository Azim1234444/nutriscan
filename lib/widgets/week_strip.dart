import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';

/// Seven days at a glance, with what was eaten on each.
///
/// Purely presentational: it is told which days to draw and what they add up
/// to, and reports taps back. Every total it shows is worked out by the
/// caller with the app's usual helpers, so this widget holds no nutrition
/// arithmetic of its own.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.today,
    required this.caloriesByDay,
    required this.onDaySelected,
    required this.onPreviousWeek,
    required this.onNextWeek,
  });

  /// The seven days to draw, Monday first, each at local midnight.
  final List<DateTime> days;

  /// The day the list below is showing, marked out here.
  final DateTime selectedDay;

  /// Today, at local midnight. Days after it cannot be chosen.
  final DateTime today;

  /// Calories per day, keyed by local midnight. Null until the week has been
  /// read, which is drawn the same way as a day nothing is known about.
  final Map<DateTime, double>? caloriesByDay;

  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onPreviousWeek;

  /// Null on the week holding today, which disables the button: the week
  /// after this one is entirely in the future.
  final VoidCallback? onNextWeek;

  /// The busiest day of the week, which every bar is drawn relative to.
  ///
  /// Never zero, so an empty week draws seven empty bars rather than dividing
  /// by nothing.
  double get _busiestDay {
    final Map<DateTime, double>? calories = caloriesByDay;
    if (calories == null || calories.isEmpty) return 1;

    double most = 1;
    for (final double value in calories.values) {
      if (value > most) most = value;
    }
    return most;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // Same surface and bottom border as the date bar above it, so the two
    // read as one header rather than two competing controls.
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onPreviousWeek,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                tooltip: 'Previous week',
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  Formatters.weekRange(days.first, days.last),
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onNextWeek,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                tooltip: 'Next week',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final DateTime day in days)
                  Expanded(
                    child: _WeekDayColumn(
                      // Keyed by the day it draws, so a column keeps its
                      // state when the week moves under it.
                      key: ValueKey<DateTime>(day),
                      day: day,
                      calories: caloriesByDay?[day],
                      busiestDay: _busiestDay,
                      isSelected: day == selectedDay,
                      // A day that has not happened yet holds nothing and
                      // cannot be opened, but still keeps its place.
                      isFuture: day.isAfter(today),
                      onTap: () => onDaySelected(day),
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

/// One day of the week: its name, a bar for that day's calories, and the
/// figure itself.
class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    super.key,
    required this.day,
    required this.calories,
    required this.busiestDay,
    required this.isSelected,
    required this.isFuture,
    required this.onTap,
  });

  final DateTime day;

  /// Null when the week has not been read yet.
  final double? calories;
  final double busiestDay;
  final bool isSelected;
  final bool isFuture;
  final VoidCallback onTap;

  /// How tall the bars are drawn.
  static const double _barHeight = 24;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // A future day is left blank rather than shown as zero: nothing was
    // eaten there because the day has not arrived.
    final double? eaten = isFuture ? null : calories;

    final Color labelColor = isSelected
        ? AppColors.primaryDark
        : isFuture
        ? AppColors.outline
        : AppColors.textSecondary;

    return Semantics(
      button: !isFuture,
      selected: isSelected,
      label:
          '${Formatters.day(day)}, '
          '${eaten == null ? 'nothing recorded' : '${Formatters.calories(eaten)} calories'}',
      child: InkWell(
        // Tapping tomorrow does nothing: there is nothing there to show.
        onTap: isFuture ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primarySoft : null,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                child: Text(
                  Formatters.weekday(day),
                  style: text.bodySmall?.copyWith(color: labelColor),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: _barHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    // The busiest day fills the bar and the rest are drawn
                    // against it, which is what makes the week readable at a
                    // glance without an axis or a label on every bar.
                    heightFactor: ((eaten ?? 0) / busiestDay).clamp(0.0, 1.0),
                    widthFactor: 0.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryDark
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  // An en dash for a day nothing is known about: either it
                  // has not happened, or the week has not been read yet.
                  eaten == null ? '–' : Formatters.calories(eaten),
                  style: text.bodySmall?.copyWith(
                    color: isSelected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
