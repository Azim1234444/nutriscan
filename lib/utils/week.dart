/// Monday-to-Sunday calendar weeks, in local time.
///
/// The only place in the app that decides where a week begins, so History
/// cannot disagree with itself. Every date here is local midnight, matching
/// how the repository decides which day a meal belongs to.
class Week {
  const Week._();

  /// Days in a week. Named so the seven below is never a bare number.
  static const int length = 7;

  /// Midnight on the day containing [time].
  ///
  /// Shared with the day view, so a day means the same thing to both.
  static DateTime dayOf(DateTime time) {
    return DateTime(time.year, time.month, time.day);
  }

  /// [days] later than [day], or earlier when negative.
  ///
  /// Counted on the calendar rather than in hours: `DateTime` rolls a day
  /// number past the end of a month over for us, and a day that is 23 or 25
  /// hours long because the clocks changed still counts as one day.
  static DateTime addDays(DateTime day, int days) {
    return DateTime(day.year, day.month, day.day + days);
  }

  /// Midnight on the Monday of the week containing [day].
  static DateTime startOf(DateTime day) {
    final DateTime date = dayOf(day);
    // DateTime.weekday is 1 for Monday, so this is 0 on a Monday and 6 on a
    // Sunday: exactly how far back the start of the week is.
    return addDays(date, DateTime.monday - date.weekday);
  }

  /// Midnight on the Sunday of the week containing [day].
  static DateTime endOf(DateTime day) => addDays(startOf(day), length - 1);

  /// The seven days of the week containing [day], Monday first.
  static List<DateTime> daysOf(DateTime day) {
    final DateTime start = startOf(day);
    return <DateTime>[for (int i = 0; i < length; i++) addDays(start, i)];
  }

  /// Whether [a] and [b] fall in the same week.
  static bool sameWeek(DateTime a, DateTime b) => startOf(a) == startOf(b);
}
