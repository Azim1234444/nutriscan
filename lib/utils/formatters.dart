import 'week.dart';

/// Small helpers that turn raw numbers and dates into display strings.
///
/// Kept in one place so "42 g" or "Today · 8:15 AM" look identical on every
/// screen. Written by hand so phase 1 needs no extra packages.
class Formatters {
  const Formatters._();

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Monday first, matching DateTime.weekday.
  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// 465.0 -> "465"
  static String calories(double value) => value.round().toString();

  /// 42.4 -> "42 g"
  static String grams(double value) => '${value.round()} g';

  /// 173.0 -> "173", 173.5 -> "173.5"
  static String measurement(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }

  /// 8:15 in the morning -> "8:15 AM"
  static String time(DateTime dateTime) {
    final int hour24 = dateTime.hour;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = dateTime.minute.toString().padLeft(2, '0');
    final String period = hour24 < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  /// "Today", "Yesterday" or "12 Aug 2026".
  ///
  /// Which of the three is decided by comparing calendar dates, not by how
  /// many hours apart they are. A local day is 23 or 25 hours long on the day
  /// the clocks change, and measuring the gap in hours read a 23-hour
  /// yesterday as being zero days away - so the History date bar called
  /// yesterday "Today" while its Today button, which compares dates, knew
  /// otherwise.
  ///
  /// [now] is only ever passed by tests, which need a fixed clock to say what
  /// "today" is without depending on when the suite runs. Production passes
  /// nothing and gets the real one.
  static String day(DateTime dateTime, {DateTime? now}) {
    final DateTime date = Week.dayOf(dateTime);
    final DateTime today = Week.dayOf(now ?? DateTime.now());

    if (date == today) return 'Today';
    if (date == Week.addDays(today, -1)) return 'Yesterday';
    return '${dateTime.day} ${_months[dateTime.month - 1]} ${dateTime.year}';
  }

  /// Monday -> "Mon". Used for the seven columns of the weekly overview.
  static String weekday(DateTime dateTime) {
    return _weekdays[dateTime.weekday - 1];
  }

  /// The span a week covers: "17 - 23 Aug 2026".
  ///
  /// The month and year are written once when both ends share them, which is
  /// what makes it short enough to sit above seven columns.
  static String weekRange(DateTime start, DateTime end) {
    final String endPart = '${end.day} ${_months[end.month - 1]} ${end.year}';

    if (start.year != end.year) {
      return '${start.day} ${_months[start.month - 1]} ${start.year} '
          '– $endPart';
    }
    if (start.month != end.month) {
      return '${start.day} ${_months[start.month - 1]} – $endPart';
    }
    return '${start.day} – $endPart';
  }

  /// "Today · 8:15 AM"
  static String dayAndTime(DateTime dateTime) {
    return '${day(dateTime)} · ${time(dateTime)}';
  }
}
