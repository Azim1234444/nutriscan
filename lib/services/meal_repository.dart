import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/nutrition_summary.dart';
import '../models/reviewed_meal.dart';
import '../models/saved_meal.dart';
import '../utils/week.dart';
import 'auth_service.dart';

/// Raised when a meal cannot be saved, read or deleted.
///
/// [message] is safe to show to the user, and the caller can offer a retry.
class MealRepositoryFailure implements Exception {
  const MealRepositoryFailure(this.message);

  final String message;

  @override
  String toString() => 'MealRepositoryFailure: $message';
}

/// Reads and writes the signed-in user's meals.
///
/// Screens depend on this interface, never on Firestore directly, so the
/// database can be swapped or faked without touching the UI.
/// How many meals the "recent meals" preview asks for.
///
/// Named here rather than on the screen because it is what bounds the query:
/// the limit belongs with the read, not with the widget that draws it.
const int kRecentMealCount = 3;

abstract class MealRepository {
  /// The user's meals, newest first, updating as they change.
  ///
  /// Reads the whole collection, so nothing on a screen should use it: the
  /// dashboard asks for a day and for the newest few instead. Kept because
  /// it is the plainest way for a test to see everything that is stored.
  Stream<List<SavedMeal>> watchMeals();

  /// The meals logged on the local calendar day containing [day], newest
  /// first, updating as they change.
  ///
  /// Every meal on that day, with no limit: a day's totals have to add up all
  /// of it, and nothing caps how many meals a day can hold.
  Stream<List<SavedMeal>> watchMealsForDay(DateTime day);

  /// The newest [limit] meals from the whole history, updating as they
  /// change.
  ///
  /// Deliberately not scoped to a day. Someone who has not eaten yet today
  /// should still see what they ate yesterday, so this reaches back as far as
  /// it needs to - it is bounded by count, not by date.
  ///
  /// Never use this for totals: it stops at [limit], so on a busy day it
  /// would silently leave meals out of the sum.
  Stream<List<SavedMeal>> watchRecentMeals({int limit});

  /// Saves [meal] and returns the document id.
  ///
  /// Passing the id returned by an earlier attempt overwrites that document
  /// instead of adding a second one, which makes a retry safe.
  Future<String> saveMeal(ReviewedMeal meal, {String? mealId});

  /// Writes a correction to a meal that is already stored.
  ///
  /// Updates the document [meal] came from, so the meal keeps its id and its
  /// place in history. Only the values a person can change are written: the
  /// AI estimate and the creation time are left exactly as they were.
  Future<void> updateMeal(SavedMeal meal);

  Future<void> deleteMeal(String mealId);

  /// The meals logged on the local calendar day containing [day].
  Future<List<SavedMeal>> mealsForDate(DateTime day);

  /// The meals logged from the day containing [firstDay] to the day
  /// containing [lastDay], both ends included, newest first.
  ///
  /// Local calendar days, exactly as [mealsForDate] reads them: passing the
  /// same day twice returns that one day. One query covers the whole span, so
  /// a week costs a single read rather than seven.
  Future<List<SavedMeal>> mealsForRange(DateTime firstDay, DateTime lastDay);

  /// Whether the user has saved at least one meal.
  ///
  /// Reads a single document at most, so it is cheap enough to ask before
  /// deciding what to warn somebody about. Never throws: a failed check
  /// answers "no" rather than blocking whatever asked.
  Future<bool> hasAnyMeals();
}

/// Totals a list of meals using the user's reviewed values.
///
/// Each meal is counted once: duplicate ids are ignored, so a list that
/// somehow contains the same meal twice cannot inflate the dashboard.
NutritionSummary totalsFor(Iterable<SavedMeal> meals) {
  NutritionSummary total = NutritionSummary.zero;

  for (final SavedMeal meal in _countedOnce(meals)) {
    total = total + meal.current.nutrition;
  }
  return total;
}

/// Fibre eaten across [meals], counting each meal once.
///
/// Kept apart from [totalsFor] because fibre is not part of
/// [NutritionSummary]: the app sets no fibre target, so there is nothing to
/// compare it against on the dashboard. History shows it because a day's
/// fibre is worth knowing on its own.
double fiberTotalFor(Iterable<SavedMeal> meals) {
  double total = 0;

  for (final SavedMeal meal in _countedOnce(meals)) {
    total += meal.current.fiberG;
  }
  return total;
}

/// Drops repeats, so a list that somehow holds the same meal twice cannot
/// inflate a total. One definition, used by every total in the app.
Iterable<SavedMeal> _countedOnce(Iterable<SavedMeal> meals) sync* {
  final Set<String> seen = <String>{};

  for (final SavedMeal meal in meals) {
    if (seen.add(meal.id)) yield meal;
  }
}

/// Keeps only the meals logged on the same local calendar day as [day].
List<SavedMeal> mealsOnDay(Iterable<SavedMeal> meals, DateTime day) {
  return meals
      .where(
        (SavedMeal meal) =>
            meal.createdAt.year == day.year &&
            meal.createdAt.month == day.month &&
            meal.createdAt.day == day.day,
      )
      .toList();
}

/// The half-open span of instants a run of local calendar days covers.
///
/// `start <= createdAt < end`, which is the comparison every day query in
/// this file makes.
class _DaySpan {
  const _DaySpan(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// [MealRepository] backed by Cloud Firestore.
///
/// Every document lives under `users/{uid}/meals/{mealId}`, so a query can
/// only ever reach the signed-in user's own data.
class FirestoreMealRepository implements MealRepository {
  FirestoreMealRepository({
    required AuthService authService,
    FirebaseFirestore? firestore,
  }) : _auth = authService,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final FirebaseFirestore _firestore;

  static const String usersCollection = 'users';
  static const String mealsCollection = 'meals';

  CollectionReference<Map<String, dynamic>> _mealsRef(String userId) {
    return _firestore
        .collection(usersCollection)
        .doc(userId)
        .collection(mealsCollection);
  }

  /// The signed-in user for work on meals that already exist.
  ///
  /// Editing and deleting act on a document written under a particular
  /// account. Without that account there is nothing to act on, and starting a
  /// session here would only invent a different one, so this refuses instead.
  String _requireSession() {
    final String? userId = _auth.currentUserId;
    if (userId == null) {
      throw const MealRepositoryFailure(
        'You are signed out. Sign in to change your meals.',
      );
    }
    return userId;
  }

  @override
  Stream<List<SavedMeal>> watchMeals() {
    // `currentUserId`, never `ensureSignedIn`: looking at meals must not be
    // the thing that brings an account into existence. Without a session
    // there is nothing stored to watch, and an empty list is the honest
    // answer - inventing an account here would hide a lost session behind a
    // new, empty one.
    final String? userId = _auth.currentUserId;
    if (userId == null) {
      return Stream<List<SavedMeal>>.value(const <SavedMeal>[]);
    }

    return _mealsRef(userId)
        .orderBy(MealFields.createdAt, descending: true)
        .snapshots()
        .map(_readSnapshot);
  }

  @override
  Stream<List<SavedMeal>> watchMealsForDay(DateTime day) {
    // `currentUserId`, never `ensureSignedIn`, for the same reason every
    // other read here does it: the dashboard rebuilding must not be what
    // brings an account into existence.
    final String? userId = _auth.currentUserId;
    if (userId == null) {
      return Stream<List<SavedMeal>>.value(const <SavedMeal>[]);
    }

    final _DaySpan span = _spanFor(day, day);

    return _mealsRef(userId)
        .where(
          MealFields.createdAt,
          isGreaterThanOrEqualTo: Timestamp.fromDate(span.start),
        )
        .where(MealFields.createdAt, isLessThan: Timestamp.fromDate(span.end))
        .orderBy(MealFields.createdAt, descending: true)
        .snapshots()
        .map(_readSnapshot);
  }

  @override
  Stream<List<SavedMeal>> watchRecentMeals({int limit = kRecentMealCount}) {
    final String? userId = _auth.currentUserId;
    if (userId == null) {
      return Stream<List<SavedMeal>>.value(const <SavedMeal>[]);
    }

    // The limit is the point: the newest few are all this can ever return,
    // however long the history behind them is.
    return _mealsRef(userId)
        .orderBy(MealFields.createdAt, descending: true)
        .limit(limit)
        .snapshots()
        .map(_readSnapshot);
  }

  @override
  Future<String> saveMeal(ReviewedMeal meal, {String? mealId}) async {
    try {
      final String userId = await _auth.ensureSignedIn();

      // An id supplied by the caller names a document this screen has already
      // written, so this is a re-save of that meal rather than a new one.
      final bool isNew = mealId == null;
      final DocumentReference<Map<String, dynamic>> document = isNew
          ? _mealsRef(userId).doc()
          : _mealsRef(userId).doc(mealId);

      await document.set(
        mealToDocument(
          meal,
          userId: userId,
          mealType: SavedMeal.mealTypeForTime(DateTime.now()),
          // Only the first write stamps the time the meal was logged. A
          // re-save leaves it alone, so correcting an estimate cannot move the
          // meal to a later day - and cannot be refused by the rules, which
          // hold `createdAt` immutable once a document exists.
          createdAt: isNew ? FieldValue.serverTimestamp() : null,
          updatedAt: FieldValue.serverTimestamp(),
        ),
        SetOptions(merge: !isNew),
      );

      return document.id;
    } on AuthFailure catch (error) {
      throw MealRepositoryFailure(error.message);
    } on FirebaseException catch (error) {
      throw MealRepositoryFailure(_messageFor(error.code, saving: true));
    } catch (_) {
      throw const MealRepositoryFailure(
        'The meal could not be saved. Please try again.',
      );
    }
  }

  @override
  Future<void> updateMeal(SavedMeal meal) async {
    try {
      final String userId = _requireSession();

      // The path below already scopes the write to the signed-in user, so
      // this cannot be reached through the app. It is here so a meal read
      // under one account can never be written back under another, whatever
      // a future caller does.
      if (meal.userId.isNotEmpty && meal.userId != userId) {
        throw const MealRepositoryFailure(
          'That meal belongs to a different account.',
        );
      }

      // `update`, not `set`: it fails if the document has gone rather than
      // quietly recreating it, so an edit can never add a second meal.
      await _mealsRef(userId)
          .doc(meal.id)
          .update(
            mealEditToDocument(meal, updatedAt: FieldValue.serverTimestamp()),
          );
    } on MealRepositoryFailure {
      rethrow;
    } on AuthFailure catch (error) {
      throw MealRepositoryFailure(error.message);
    } on FirebaseException catch (error) {
      throw MealRepositoryFailure(_messageFor(error.code, saving: true));
    } catch (_) {
      throw const MealRepositoryFailure(
        'The changes could not be saved. Please try again.',
      );
    }
  }

  @override
  Future<void> deleteMeal(String mealId) async {
    try {
      final String userId = _requireSession();
      await _mealsRef(userId).doc(mealId).delete();
    } on AuthFailure catch (error) {
      throw MealRepositoryFailure(error.message);
    } on FirebaseException catch (error) {
      throw MealRepositoryFailure(_messageFor(error.code, saving: false));
    } catch (_) {
      throw const MealRepositoryFailure(
        'The meal could not be deleted. Please try again.',
      );
    }
  }

  @override
  Future<bool> hasAnyMeals() async {
    // Deliberately `currentUserId` rather than `ensureSignedIn`: this is a
    // read, and a read must never bring an account into existence. Without a
    // session there is nothing stored, which is the honest answer anyway.
    final String? userId = _auth.currentUserId;
    if (userId == null) return false;

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _mealsRef(
        userId,
      ).limit(1).get();
      return snapshot.docs.isNotEmpty;
    } catch (_) {
      // Used only to choose a warning, so a failure must not stop the user.
      return false;
    }
  }

  @override
  Future<List<SavedMeal>> mealsForDate(DateTime day) => mealsForRange(day, day);

  @override
  Future<List<SavedMeal>> mealsForRange(DateTime firstDay, DateTime lastDay) {
    final _DaySpan span = _spanFor(firstDay, lastDay);

    return _mealsBetween(span.start, span.end);
  }

  /// Midnight on the first day, to midnight after the last.
  ///
  /// The one place a calendar day's edges are worked out, so the day History
  /// reads and the day the dashboard totals can never be different days.
  ///
  /// Both edges come from `Week`, which counts on the calendar. Adding a
  /// `Duration` of 24 hours would not do: on the day the clocks change a
  /// local day is 23 or 25 hours long, so 24 hours after midnight is an hour
  /// either side of the next one - which either hid the last hour of a day
  /// from it or counted the first hour of the next day twice.
  static _DaySpan _spanFor(DateTime firstDay, DateTime lastDay) {
    return _DaySpan(Week.dayOf(firstDay), Week.addDays(lastDay, 1));
  }

  /// Reads the meals with `start <= createdAt < end`, newest first.
  Future<List<SavedMeal>> _mealsBetween(DateTime start, DateTime end) async {
    // A day or a week is only ever read, so this asks who is signed in
    // rather than signing anybody in. Someone browsing History on a device
    // with no session sees empty days, which is what is actually there.
    final String? userId = _auth.currentUserId;
    if (userId == null) return const <SavedMeal>[];

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _mealsRef(userId)
              .where(
                MealFields.createdAt,
                isGreaterThanOrEqualTo: Timestamp.fromDate(start),
              )
              .where(MealFields.createdAt, isLessThan: Timestamp.fromDate(end))
              .orderBy(MealFields.createdAt, descending: true)
              .get();

      return _readSnapshot(snapshot);
    } on AuthFailure catch (error) {
      throw MealRepositoryFailure(error.message);
    } on FirebaseException catch (error) {
      throw MealRepositoryFailure(_messageFor(error.code, saving: false));
    } catch (_) {
      throw const MealRepositoryFailure(
        'Your meals could not be loaded. Please try again.',
      );
    }
  }

  /// Turns a query snapshot into meals, skipping any document that cannot be
  /// read rather than failing the whole list.
  List<SavedMeal> _readSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final List<SavedMeal> meals = <SavedMeal>[];

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in snapshot.docs) {
      final SavedMeal? meal = mealFromDocument(document.id, document.data());
      if (meal != null) meals.add(meal);
    }
    return meals;
  }

  String _messageFor(String code, {required bool saving}) {
    switch (code) {
      case 'permission-denied':
        return 'You do not have access to these meals.';
      case 'not-found':
        return 'That meal is no longer in your history.';
      case 'unavailable':
      case 'network-request-failed':
        return 'No connection to the meal database. Please try again.';
      case 'deadline-exceeded':
        return 'The request took too long. Please try again.';
      default:
        return saving
            ? 'The meal could not be saved. Please try again.'
            : 'Your meals could not be loaded. Please try again.';
    }
  }
}
