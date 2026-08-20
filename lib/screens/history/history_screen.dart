import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/services_scope.dart';
import '../../models/food_entry.dart';
import '../../models/macro.dart';
import '../../models/nutrition_summary.dart';
import '../../models/saved_meal.dart';
import '../../services/meal_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/macro_visuals.dart';
import '../../utils/formatters.dart';
import '../../utils/week.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/food_history_card.dart';
import '../../widgets/week_strip.dart';

/// The History tab: one day at a time, with what was eaten that day.
///
/// Opens on today and reads only the selected day from the repository, so
/// looking back through a long history never means loading all of it.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.isActive = true,
    this.clock = DateTime.now,
  });

  /// Whether this is the tab currently being looked at.
  ///
  /// The shell keeps every tab alive, so History is never rebuilt from scratch
  /// and would otherwise go on showing the day it read when the app started.
  /// Being told when it comes back into view gives it the one moment worth
  /// catching up in: a meal saved from the scan flow is stored by then, and a
  /// day that ended while this was out of view has ended for good.
  final bool isActive;

  /// Reads the current time.
  ///
  /// Only ever replaced by tests, which need to move the clock past midnight
  /// to check what happens to the selected day. Production passes nothing and
  /// gets the real one.
  final DateTime Function() clock;

  /// How far back the date picker will go.
  ///
  /// Earlier than any NutriScan account can hold meals, so it never gets in
  /// the way, while still giving the picker a real lower bound.
  static final DateTime earliestDate = DateTime(2020);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// The day being shown, always at midnight local time.
  late DateTime _selectedDate = _today;

  /// True while the screen is meant to keep up with the current day.
  ///
  /// Set whenever the day chosen happens to be today and cleared as soon as
  /// another one is picked, so a day ending while History is out of view moves
  /// the screen on only for somebody who was actually looking at today.
  /// Someone who deliberately went back to Tuesday is still on Tuesday when
  /// they return.
  bool _followsToday = true;

  /// The meals for [_selectedDate]. Replaced whenever the day changes or the
  /// list needs re-reading after an edit, a delete, or a return to this tab.
  Future<List<SavedMeal>>? _meals;

  /// The meals for the whole week holding [_selectedDate], read in one query
  /// and used only for the seven day totals in the strip.
  Future<List<SavedMeal>>? _weekMeals;

  /// The repository the reads go through.
  ///
  /// Held from [didChangeDependencies] so that returning to the tab can start
  /// a read from [didUpdateWidget], where looking the scope up again would be
  /// the wrong place to do it.
  late MealRepository _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = ServicesScope.of(context).mealRepository;
    // The first read waits until the services are reachable, and until this
    // tab is actually being looked at: the shell builds all four at once, so
    // reading regardless would spend a query on a screen nobody has opened.
    if (widget.isActive) _readIfNeeded();
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Coming back to the tab is the moment to catch up. `build` runs straight
    // after this, so the replaced futures are picked up without a setState.
    if (widget.isActive && !oldWidget.isActive) _catchUp();
  }

  /// Midnight on the day containing [time], matching how the repository
  /// decides which day a meal belongs to.
  static DateTime _dayOf(DateTime time) => Week.dayOf(time);

  /// Midnight today, by the one definition of a day this screen uses.
  DateTime get _today => _dayOf(widget.clock());

  bool get _isToday => _selectedDate == _today;

  /// The week the selected day falls in. Derived rather than stored, so the
  /// strip can never end up showing a week the selected day is not in.
  List<DateTime> get _week => Week.daysOf(_selectedDate);

  Future<List<SavedMeal>> _read() => _repository.mealsForDate(_selectedDate);

  Future<List<SavedMeal>> _readWeek() {
    final List<DateTime> week = _week;
    return _repository.mealsForRange(week.first, week.last);
  }

  /// Starts the first read of the day and its week, if they have not run.
  void _readIfNeeded() {
    _meals ??= _read();
    _weekMeals ??= _readWeek();
  }

  /// Brings the screen back in step with the clock and with what is stored.
  ///
  /// Both reads are replaced rather than kept: a meal saved from another tab
  /// belongs to the day list and to the week totals above it, and neither can
  /// notice it on its own.
  void _catchUp() {
    if (_followsToday) _selectedDate = _today;

    _meals = _read();
    _weekMeals = _readWeek();
  }

  /// Re-reads the selected day, after an edit or a delete changed it.
  void _refresh() {
    if (!mounted) return;
    // A block body, not an arrow: an arrow would hand setState the
    // assignment's value - a Future - which it rejects.
    setState(() {
      _meals = _read();
      // The week totals hold the meal that just changed too.
      _weekMeals = _readWeek();
    });
  }

  /// Shows [day], unless it is the day already on screen.
  void _show(DateTime day) {
    final DateTime date = _dayOf(day);
    if (date == _selectedDate) return;

    final bool sameWeek = Week.sameWeek(date, _selectedDate);

    setState(() {
      _selectedDate = date;
      // Choosing today is what puts the screen back on the clock; choosing
      // any other day takes it off.
      _followsToday = date == _today;
      _meals = _read();
      // Only re-read the seven days when the day chosen is in another week.
      if (!sameWeek) _weekMeals = _readWeek();
    });
  }

  void _showPreviousDay() => _show(Week.addDays(_selectedDate, -1));

  /// Moves a day forward, which the button hides on today: there is nothing
  /// to see in the future, and a meal cannot be logged there.
  void _showNextDay() {
    if (_isToday) return;
    _show(Week.addDays(_selectedDate, 1));
  }

  void _showToday() => _show(widget.clock());

  /// The same weekday a week earlier, which brings the strip back with it.
  void _showPreviousWeek() => _show(Week.addDays(_selectedDate, -Week.length));

  /// A week forward, without ever landing after today.
  ///
  /// Clamping rather than refusing keeps the button useful from a part-way
  /// week: moving on from last Saturday lands on today, not on a day that
  /// has not happened.
  void _showNextWeek() {
    final DateTime today = _today;
    if (Week.sameWeek(_selectedDate, today)) return;

    final DateTime next = Week.addDays(_selectedDate, Week.length);
    _show(next.isAfter(today) ? today : next);
  }

  Future<void> _pickDate() async {
    final DateTime today = _today;
    final DateTime? chosen = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: HistoryScreen.earliestDate,
      // Today is the last day that can hold anything.
      lastDate: today,
      helpText: 'Jump to a day',
    );

    if (chosen != null) _show(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _DateBar(
              date: _selectedDate,
              isToday: _isToday,
              onPrevious: _showPreviousDay,
              onNext: _isToday ? null : _showNextDay,
              onPickDate: _pickDate,
              onToday: _showToday,
            ),
            FutureBuilder<List<SavedMeal>>(
              future: _weekMeals,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<SavedMeal>> snapshot,
                  ) {
                    final List<DateTime> week = _week;
                    final DateTime today = _today;

                    return WeekStrip(
                      days: week,
                      selectedDay: _selectedDate,
                      today: today,
                      // A week that has not arrived, or could not be read,
                      // is drawn empty: the day below is what matters, and
                      // it reports its own trouble.
                      caloriesByDay: snapshot.hasError || !snapshot.hasData
                          ? null
                          : _caloriesByDay(week, snapshot.data!),
                      onDaySelected: _show,
                      onPreviousWeek: _showPreviousWeek,
                      onNextWeek: Week.sameWeek(_selectedDate, today)
                          ? null
                          : _showNextWeek,
                    );
                  },
            ),
            Expanded(
              child: FutureBuilder<List<SavedMeal>>(
                // Keyed by day, so a slow read for one day can never paint
                // its meals under another.
                key: ValueKey<DateTime>(_selectedDate),
                future: _meals,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<SavedMeal>> snapshot,
                    ) {
                      if (snapshot.hasError) {
                        return const EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Meals could not be loaded',
                          message:
                              'Check your connection and reopen this tab to '
                              'try again.',
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final List<SavedMeal> meals =
                          snapshot.data ?? const <SavedMeal>[];
                      if (meals.isEmpty) {
                        return _isToday
                            ? const EmptyState(
                                icon: Icons.history_rounded,
                                title: 'No meals saved yet.',
                                message:
                                    'Scan a meal and save it to see it listed '
                                    'here with its calories and macros.',
                              )
                            : const EmptyState(
                                icon: Icons.history_rounded,
                                title: 'No meals on this day.',
                                message:
                                    'Nothing was saved on this date. Use the '
                                    'arrows to look at another day.',
                              );
                      }

                      return _MealList(meals: meals, onChanged: _refresh);
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The day being shown, with a way to either side of it.
class _DateBar extends StatelessWidget {
  const _DateBar({
    required this.date,
    required this.isToday,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
    required this.onToday,
  });

  final DateTime date;
  final bool isToday;
  final VoidCallback onPrevious;

  /// Null on today, which disables the button: there is no day after this one.
  final VoidCallback? onNext;
  final VoidCallback onPickDate;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous day',
          ),
          Expanded(
            child: InkWell(
              onTap: onPickDate,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        Formatters.day(date),
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next day',
          ),
          // Only worth offering once there is somewhere to come back from.
          if (!isToday)
            TextButton(onPressed: onToday, child: const Text('Today')),
        ],
      ),
    );
  }
}

/// The selected day's meals, with that day's totals on top.
class _MealList extends StatelessWidget {
  const _MealList({required this.meals, required this.onChanged});

  final List<SavedMeal> meals;

  /// Called once a meal on this day has been changed or removed.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        _DaySummary(meals: meals),
        const SizedBox(height: AppSpacing.lg),
        for (final SavedMeal meal in meals)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _MealListItem(meal: meal, onChanged: onChanged),
          ),
      ],
    );
  }
}

/// What the overflow menu on a meal card offers.
enum _MealAction { edit, delete }

/// One meal in the list, with the actions that apply to it.
///
/// Stateful only to hold the "a write is already running" flag: deleting is
/// the one action here that cannot be undone, so it must not be possible to
/// start it twice.
class _MealListItem extends StatefulWidget {
  const _MealListItem({required this.meal, required this.onChanged});

  final SavedMeal meal;

  /// Tells the list to re-read the day once this meal has changed.
  final VoidCallback onChanged;

  @override
  State<_MealListItem> createState() => _MealListItemState();
}

class _MealListItemState extends State<_MealListItem> {
  /// True while a delete is in flight.
  bool _isDeleting = false;

  /// Opens the editor, then re-reads the day so any correction shows.
  Future<void> _edit() async {
    if (_isDeleting) return;

    await Navigator.of(context)
        .pushNamed<bool>(AppRoutes.editMeal, arguments: widget.meal);

    if (mounted) widget.onChanged();
  }

  /// Asks before removing the meal, since nothing can bring it back.
  Future<bool> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete this meal?'),
          content: Text(
            '${widget.meal.current.foodName} will be removed from your '
            'history. This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Confirms, then deletes. Returns true only once the meal is really gone.
  ///
  /// The swipe uses the answer to decide whether the card may leave the
  /// screen, so a failed delete has to report false: the meal is still there
  /// and must stay visible.
  Future<bool> _confirmAndDelete() async {
    if (_isDeleting) return false;
    if (!await _confirmDelete()) return false;
    if (!mounted) return false;

    final MealRepository repository = ServicesScope.of(context).mealRepository;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String name = widget.meal.current.foodName;

    setState(() => _isDeleting = true);

    try {
      await repository.deleteMeal(widget.meal.id);
    } on MealRepositoryFailure catch (error) {
      // Nothing was removed, so say why and leave the meal where it is.
      if (mounted) setState(() => _isDeleting = false);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    }

    messenger.showSnackBar(SnackBar(content: Text('$name deleted')));
    return true;
  }

  /// The menu route: the card is still on screen, so the day is re-read here.
  Future<void> _deleteFromMenu() async {
    if (await _confirmAndDelete() && mounted) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final SavedMeal meal = widget.meal;
    final FoodEntry entry = meal.toFoodEntry();

    return Dismissible(
      key: ValueKey<String>(meal.id),
      direction: DismissDirection.endToStart,
      // The delete happens here rather than in onDismissed, so a card only
      // ever leaves the list when the meal has actually gone.
      confirmDismiss: (DismissDirection _) => _confirmAndDelete(),
      // Reached only after a delete that succeeded, once the card is away.
      onDismissed: (DismissDirection _) => widget.onChanged(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: AppRadius.cardRadius,
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: FoodHistoryCard(
        entry: entry,
        isEdited: meal.isEdited,
        aiNote: _aiNote(meal),
        menu: PopupMenuButton<_MealAction>(
          // Closed while a delete runs, so a second one cannot be started.
          enabled: !_isDeleting,
          tooltip: 'Meal actions',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (_MealAction action) {
            switch (action) {
              case _MealAction.edit:
                _edit();
              case _MealAction.delete:
                _deleteFromMenu();
            }
          },
          itemBuilder: (BuildContext context) {
            return const <PopupMenuEntry<_MealAction>>[
              PopupMenuItem<_MealAction>(
                value: _MealAction.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<_MealAction>(
                value: _MealAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ];
          },
        ),
      ),
    );
  }
}

/// What each of [days] adds up to, out of one week's meals.
///
/// Built from the two helpers the day total and the dashboard already use:
/// `mealsOnDay` decides which day a meal belongs to, and `totalsFor` adds
/// the day up counting each meal once. No calorie is worked out here, which
/// is why the strip can never disagree with the day below it.
Map<DateTime, double> _caloriesByDay(
  List<DateTime> days,
  List<SavedMeal> meals,
) {
  return <DateTime, double>{
    for (final DateTime day in days)
      day: totalsFor(mealsOnDay(meals, day)).calories,
  };
}

/// The model's own calorie figure, for a meal whose number the user changed.
///
/// Only shown when the two differ: on an untouched meal the card is already
/// showing the AI's number, and repeating it would say nothing.
String? _aiNote(SavedMeal meal) {
  if (!meal.isEdited) return null;
  if (meal.aiEstimate.calories == meal.current.calories) return null;
  return 'AI ${Formatters.calories(meal.aiEstimate.calories)}';
}

/// What was eaten on the selected day.
///
/// The numbers come from the same helpers the dashboard uses, so History and
/// the dashboard can never disagree about today.
class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.meals});

  final List<SavedMeal> meals;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final NutritionSummary total = totalsFor(meals);
    final double fiber = fiberTotalFor(meals);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Day total', style: text.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              _SummaryStat(
                label: 'Meals',
                value: meals.length.toString(),
                color: AppColors.primaryDark,
              ),
              _SummaryStat(
                label: 'Calories',
                value: Formatters.calories(total.calories),
                color: AppColors.primaryDark,
              ),
              for (final Macro macro in Macro.values)
                _SummaryStat(
                  label: macro.label,
                  value: Formatters.grams(macro.valueIn(total)),
                  color: MacroVisuals.color(macro),
                ),
              _SummaryStat(
                label: 'Fibre',
                value: Formatters.grams(fiber),
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: text.titleMedium?.copyWith(color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: text.bodySmall, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
