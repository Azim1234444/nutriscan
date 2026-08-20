// Tests for the display formatters.
//
// The date label is the part worth testing on its own. Phase 2S-3 found it
// deciding between "Today", "Yesterday" and a date by measuring the gap in
// hours: `today.difference(date).inDays`. A local day is 23 or 25 hours long
// on the day the clocks change, so a 23-hour yesterday measured as zero days
// away and was labelled "Today" - on the same screen whose Today button,
// which compares dates, knew it was not.
//
// The fix compares calendar dates. These lock that in.
//
// A note on daylight saving: `DateTime` follows the machine's own zone and
// there is no way to move it from inside a test without a timezone package.
// This machine is UTC+8, which has no transitions, so the DST cases below
// cannot reproduce the original fault here - they are written as calendar
// dates spanning real transitions so that they exercise the same code path,
// and they are what fails on a developer or CI machine in a zone that does
// observe it.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/utils/formatters.dart';

void main() {
  group('Formatters.day', () {
    // A fixed clock, so the labels do not depend on when the suite runs.
    // Without it a run that crossed local midnight would flip every answer.
    final DateTime now = DateTime(2026, 8, 20, 14, 30);

    test('1. the same calendar date is Today', () {
      expect(Formatters.day(DateTime(2026, 8, 20), now: now), 'Today');
    });

    test('2. the calendar date before is Yesterday', () {
      expect(Formatters.day(DateTime(2026, 8, 19), now: now), 'Yesterday');
    });

    test('3. two days back is written out', () {
      expect(Formatters.day(DateTime(2026, 8, 18), now: now), '18 Aug 2026');
    });

    test('4. the time of day is ignored, at either end of it', () {
      // Every moment of today is Today, and every moment of yesterday is
      // Yesterday: the label is about the date, not the hour.
      for (final DateTime moment in <DateTime>[
        DateTime(2026, 8, 20),
        DateTime(2026, 8, 20, 12),
        DateTime(2026, 8, 20, 23, 59, 59, 999, 999),
      ]) {
        expect(Formatters.day(moment, now: now), 'Today', reason: '$moment');
      }
      for (final DateTime moment in <DateTime>[
        DateTime(2026, 8, 19),
        DateTime(2026, 8, 19, 23, 59, 59, 999, 999),
      ]) {
        expect(
          Formatters.day(moment, now: now),
          'Yesterday',
          reason: '$moment',
        );
      }
      // ...and the clock inside `now` makes no difference either.
      expect(
        Formatters.day(DateTime(2026, 8, 19), now: DateTime(2026, 8, 20)),
        'Yesterday',
      );
    });

    test('5. a future date is written out rather than called Today', () {
      expect(Formatters.day(DateTime(2026, 8, 21), now: now), '21 Aug 2026');
    });

    group('across daylight-saving transitions', () {
      // Spring forward in the EU: Sunday 29 March 2026 is 23 hours long.
      // Measured in hours, the gap from Monday back to it is 23, which
      // truncates to zero days - the old code called it "Today".
      test('6. the 23-hour day before today is still Yesterday', () {
        expect(
          Formatters.day(
            DateTime(2026, 3, 29),
            now: DateTime(2026, 3, 30, 9),
          ),
          'Yesterday',
        );
      });

      test('7. the 23-hour day is Today while it is running', () {
        expect(
          Formatters.day(
            DateTime(2026, 3, 29),
            now: DateTime(2026, 3, 29, 23),
          ),
          'Today',
        );
      });

      test('8. the day before the 23-hour day is written out', () {
        expect(
          Formatters.day(
            DateTime(2026, 3, 28),
            now: DateTime(2026, 3, 30, 9),
          ),
          '28 Mar 2026',
        );
      });

      // Fall back in the EU: Sunday 25 October 2026 is 25 hours long.
      test('9. the 25-hour day before today is Yesterday', () {
        expect(
          Formatters.day(
            DateTime(2026, 10, 25),
            now: DateTime(2026, 10, 26, 9),
          ),
          'Yesterday',
        );
      });

      test('10. the 25-hour day is Today while it is running', () {
        expect(
          Formatters.day(
            DateTime(2026, 10, 25),
            now: DateTime(2026, 10, 25, 23),
          ),
          'Today',
        );
      });

      test('11. two days back across a transition is written out', () {
        expect(
          Formatters.day(
            DateTime(2026, 10, 24),
            now: DateTime(2026, 10, 26, 9),
          ),
          '24 Oct 2026',
        );
      });
    });

    group('rolling over the calendar', () {
      test('12. yesterday across a month boundary', () {
        expect(
          Formatters.day(DateTime(2026, 7, 31), now: DateTime(2026, 8, 1, 10)),
          'Yesterday',
        );
      });

      test('13. yesterday across a year boundary', () {
        expect(
          Formatters.day(DateTime(2025, 12, 31), now: DateTime(2026, 1, 1, 10)),
          'Yesterday',
        );
      });

      test('14. yesterday across the leap day', () {
        expect(
          Formatters.day(DateTime(2028, 2, 29), now: DateTime(2028, 3, 1, 10)),
          'Yesterday',
        );
      });
    });

    test('15. with no clock passed it reads the real one', () {
      // The production call takes no `now`. Whatever today is when this runs,
      // it must be Today - and the day before it Yesterday.
      final DateTime today = DateTime.now();
      expect(Formatters.day(today), 'Today');
      expect(
        Formatters.day(DateTime(today.year, today.month, today.day - 1)),
        'Yesterday',
      );
    });
  });

  group('Formatters.dayAndTime', () {
    test('16. joins the date label to the clock time', () {
      expect(
        Formatters.dayAndTime(DateTime.now()),
        startsWith('Today · '),
      );
    });
  });
}
