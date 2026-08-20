import 'dart:async';

import 'package:nutriscan/models/food_analysis_result.dart';
import 'package:nutriscan/models/food_entry.dart';
import 'package:nutriscan/models/reviewed_meal.dart';
import 'package:nutriscan/models/saved_meal.dart';
import 'package:nutriscan/services/auth_service.dart';
import 'package:nutriscan/models/user_profile.dart';
import 'package:nutriscan/services/meal_repository.dart';
import 'package:nutriscan/services/profile_repository.dart';
import 'package:nutriscan/utils/week.dart';

/// A fixed analysis, standing in for whatever Gemini returned.
FoodAnalysisResult buildAnalysis({
  String foodName = 'Grilled chicken salad',
  double calories = 580,
  double portionGrams = 320,
  double proteinG = 42,
  double carbsG = 18,
  double fatG = 24,
  double fiberG = 6,
  double confidence = 0.85,
}) {
  return FoodAnalysisResult(
    foodName: foodName,
    description: 'Mixed leaves with sliced grilled chicken breast.',
    portionGrams: portionGrams,
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    fiberG: fiberG,
    confidence: confidence,
    assumptions: const <String>['Dressing assumed to be olive oil based.'],
    items: const <AnalyzedFoodItem>[
      AnalyzedFoodItem(name: 'Grilled chicken breast', portionGrams: 150),
    ],
  );
}

/// A meal as it would come back from Firestore.
SavedMeal buildSavedMeal({
  required String id,
  required DateTime createdAt,
  String foodName = 'Grilled chicken salad',
  double calories = 580,
  double proteinG = 42,
  double carbsG = 18,
  double fatG = 24,
  bool isEdited = false,
  String userId = 'user-a',
}) {
  final FoodAnalysisResult analysis = buildAnalysis(
    foodName: foodName,
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );

  return SavedMeal(
    id: id,
    userId: userId,
    mealType: MealType.lunch,
    aiEstimate: analysis,
    current: analysis,
    isEdited: isEdited,
    createdAt: createdAt,
  );
}

/// An [AuthService] that hands out a fixed user id.
class FakeAuthService implements AuthService {
  FakeAuthService({this.userId = 'user-a', this.failure, this.existingUserId});

  /// Id of the anonymous session this device starts with.
  String userId;

  /// Id of the account [signInWithEmailPassword] recovers.
  ///
  /// A different value models the real thing: signing in returns whatever id
  /// that account was created with, not the one this device was using.
  final String? existingUserId;

  /// Overrides [existingUserId] partway through a test, so one test can sign
  /// out of one account and in to another.
  String? existingUserIdOverride;

  /// When set, [ensureSignedIn] throws this instead of signing in.
  final AuthFailure? failure;

  int signInCalls = 0;
  bool signedOut = false;

  /// How many times a session had to be started because there was none.
  ///
  /// Asking for the current session again returns the same account, exactly
  /// as Firebase does, so this only moves when a genuinely new anonymous
  /// session is created.
  int sessionsCreated = 0;

  /// The session this device is holding, or null when it has none.
  ///
  /// Held on its own rather than worked out from a call count: whether a
  /// session exists and whether one was just created are different questions,
  /// and every read in the app now turns on telling them apart.
  String? _sessionUserId;

  @override
  String? get currentUserId => _sessionUserId;

  @override
  bool get isSignedIn => currentUserId != null;

  /// Puts the fake in the state of a device that already has a session.
  ///
  /// Reads are meant to use a session that is already there and never to
  /// start one, so a test about reading has to say which case it is testing.
  /// This counts towards [sessionsCreated]: the session did have to be
  /// created at some point, just not by the read under test - so a read that
  /// wrongly creates another one still shows up as a change.
  void beginSession({bool anonymous = true}) {
    _sessionUserId = userId;
    this.anonymous = anonymous;
    sessionsCreated++;
  }

  /// Email on the account, set by linking or signing in.
  String? email;

  @override
  String? get currentUserEmail => isSignedIn ? email : null;

  @override
  Future<String> ensureSignedIn() async {
    final bool hadSession = _sessionUserId != null;
    signInCalls++;
    final AuthFailure? error = failure;
    if (error != null) throw error;
    if (!hadSession) sessionsCreated++;
    _sessionUserId = userId;
    // A session started this way is always a fresh anonymous one, which is
    // what makes an unwanted call here visible to a test.
    anonymous ??= true;
    return userId;
  }

  /// Whether the session is anonymous. Null models "nobody signed in yet".
  bool? anonymous = true;

  /// Emails passed to [linkEmailPassword]; passwords are deliberately not kept.
  final List<String> linkedEmails = <String>[];

  /// When set, [linkEmailPassword] throws this instead of linking.
  AuthFailure? linkFailure;

  @override
  bool? get isAnonymous => anonymous;

  @override
  Future<String> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    final String id = await ensureSignedIn();

    final AuthFailure? failure = linkFailure;
    if (failure != null) {
      // Firebase ends the session when it finds the account it was holding
      // has gone, so a failure of that kind takes the session with it here
      // too. Anything else leaves the session exactly where it was.
      if (failure is AuthSessionLost) {
        _sessionUserId = null;
        anonymous = null;
        this.email = null;
      }
      throw failure;
    }
    if (anonymous == false) {
      throw const AuthFailure('This device already has a saved account.');
    }

    linkedEmails.add(email);
    this.email = email;
    anonymous = false;
    // The same id comes back: linking never swaps the account.
    return id;
  }

  /// Emails passed to [signInWithEmailPassword]; passwords are not kept.
  final List<String> signedInEmails = <String>[];

  /// Emails passed to [sendPasswordResetEmail].
  final List<String> resetEmails = <String>[];

  /// When set, [signInWithEmailPassword] throws this instead of signing in.
  AuthFailure? signInFailure;

  /// When set, [sendPasswordResetEmail] throws this instead of sending.
  AuthFailure? resetFailure;

  @override
  Future<String> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final AuthFailure? failure = signInFailure;
    if (failure != null) throw failure;

    signedInEmails.add(email);
    // The recovered account's own id takes over, exactly as Firebase would
    // return it. Nothing is copied between the two.
    userId = existingUserIdOverride ?? existingUserId ?? userId;
    signInCalls = signInCalls == 0 ? 1 : signInCalls + 1;
    _sessionUserId = userId;
    anonymous = false;
    this.email = email;
    return userId;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    final AuthFailure? failure = resetFailure;
    if (failure != null) throw failure;
    resetEmails.add(email);
  }

  /// When set, [signOut] throws this instead of ending the session.
  AuthFailure? signOutFailure;

  @override
  Future<void> signOut() async {
    final AuthFailure? failure = signOutFailure;
    if (failure != null) throw failure;

    signedOut = true;
    // Back to having no session at all, exactly as Firebase leaves it. The
    // stored account is untouched: only this device forgets it.
    signInCalls = 0;
    _sessionUserId = null;
    anonymous = null;
    email = null;
  }
}

/// An in-memory [MealRepository] for screen tests.
class FakeMealRepository implements MealRepository {
  FakeMealRepository({List<SavedMeal>? meals})
    : _meals = List<SavedMeal>.of(meals ?? const <SavedMeal>[]);

  final List<SavedMeal> _meals;
  final StreamController<List<SavedMeal>> _changes =
      StreamController<List<SavedMeal>>.broadcast();

  /// How many times a save was attempted, so tests can spot duplicate writes.
  int saveCalls = 0;

  /// Ids passed to [deleteMeal], newest last.
  final List<String> deletedIds = <String>[];

  /// Meals passed to [updateMeal], newest last - what a screen actually asked
  /// to be written, before this fake applied it.
  final List<SavedMeal> updatedMeals = <SavedMeal>[];

  /// How many times each write was attempted, including attempts that were
  /// still in flight, so a test can spot a duplicate submission.
  int updateCalls = 0;
  int deleteCalls = 0;

  /// When set, [saveMeal] throws this instead of storing anything.
  MealRepositoryFailure? saveFailure;

  /// When set, [updateMeal] throws this instead of writing.
  MealRepositoryFailure? updateFailure;

  /// When set, [deleteMeal] throws this instead of removing anything.
  MealRepositoryFailure? deleteFailure;

  /// Holds an update or a delete open until a test completes it, so a write
  /// can be caught mid-flight and a second attempt made while it runs.
  Completer<void>? writeGate;

  /// Waits for [writeGate], if a test has set one.
  Future<void> _awaitGate() async {
    final Completer<void>? gate = writeGate;
    if (gate != null) await gate.future;
  }

  List<SavedMeal> get meals => List<SavedMeal>.unmodifiable(_sorted());

  /// Replaces every meal, standing in for a query scoped to another account.
  void replaceAll(List<SavedMeal> replacements) {
    _meals
      ..clear()
      ..addAll(replacements);
    _changes.add(_sorted());
  }

  List<SavedMeal> _sorted() {
    return List<SavedMeal>.of(_meals)
      ..sort((SavedMeal a, SavedMeal b) => b.createdAt.compareTo(a.createdAt));
  }

  void dispose() => _changes.close();

  /// When set, every live meal stream reports this instead of meals.
  MealRepositoryFailure? watchFailure;

  /// How many times each live read was asked for, so a test can see the
  /// dashboard building its streams once rather than on every rebuild.
  int watchMealsCalls = 0;
  int watchMealsForDayCalls = 0;
  int watchRecentMealsCalls = 0;

  /// Live subscriptions currently open on this repository, and the most that
  /// were ever open at once.
  ///
  /// The pair matters: a count that goes up and down is churn, a peak above
  /// the number of streams in use is a leak. They are different faults.
  int activeListeners = 0;
  int peakListeners = 0;

  /// Days passed to [watchMealsForDay], oldest first.
  final List<DateTime> daysWatched = <DateTime>[];

  /// Limits passed to [watchRecentMeals], oldest first.
  final List<int> recentLimits = <int>[];

  /// Wraps [source] so listening and cancelling are counted.
  Stream<List<SavedMeal>> _tracked(Stream<List<SavedMeal>> source) {
    late final StreamController<List<SavedMeal>> controller;
    StreamSubscription<List<SavedMeal>>? subscription;

    controller = StreamController<List<SavedMeal>>(
      onListen: () {
        activeListeners++;
        if (activeListeners > peakListeners) peakListeners = activeListeners;
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        activeListeners--;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// The current value followed by every later one, or a failure throughout.
  Stream<List<SavedMeal>> _live(
    List<SavedMeal> Function(List<SavedMeal>) select,
  ) async* {
    final MealRepositoryFailure? failure = watchFailure;
    if (failure != null) throw failure;

    yield select(_sorted());
    yield* _changes.stream.map(select);
  }

  @override
  Stream<List<SavedMeal>> watchMeals() {
    watchMealsCalls++;
    return _tracked(_live((List<SavedMeal> meals) => meals));
  }

  @override
  Stream<List<SavedMeal>> watchMealsForDay(DateTime day) {
    watchMealsForDayCalls++;
    daysWatched.add(DateTime(day.year, day.month, day.day));
    return _tracked(
      _live((List<SavedMeal> meals) => mealsOnDay(meals, day)),
    );
  }

  @override
  Stream<List<SavedMeal>> watchRecentMeals({int limit = kRecentMealCount}) {
    watchRecentMealsCalls++;
    recentLimits.add(limit);
    return _tracked(
      _live((List<SavedMeal> meals) => meals.take(limit).toList()),
    );
  }

  @override
  Future<String> saveMeal(ReviewedMeal meal, {String? mealId}) async {
    saveCalls++;
    final MealRepositoryFailure? failure = saveFailure;
    if (failure != null) throw failure;

    final String id = mealId ?? 'meal-${_meals.length + 1}';
    final SavedMeal saved = SavedMeal(
      id: id,
      userId: 'user-a',
      mealType: SavedMeal.mealTypeForTime(DateTime.now()),
      aiEstimate: meal.aiEstimate,
      current: meal.current,
      isEdited: meal.isEdited,
      createdAt: DateTime.now(),
    );

    // Writing to a known id replaces that meal instead of adding another.
    _meals.removeWhere((SavedMeal existing) => existing.id == id);
    _meals.add(saved);
    _changes.add(_sorted());
    return id;
  }

  @override
  Future<void> updateMeal(SavedMeal meal) async {
    updateCalls++;
    await _awaitGate();

    final MealRepositoryFailure? failure = updateFailure;
    if (failure != null) throw failure;

    final int index = _meals.indexWhere(
      (SavedMeal existing) => existing.id == meal.id,
    );
    if (index < 0) {
      throw const MealRepositoryFailure(
        'That meal is no longer in your history.',
      );
    }

    updatedMeals.add(meal);

    // Mirrors the real write, which never sends the id, the owner, the
    // creation time or the AI estimate: whatever a caller puts in those
    // fields, the stored document keeps its own.
    final SavedMeal stored = _meals[index];
    _meals[index] = SavedMeal(
      id: stored.id,
      userId: stored.userId,
      mealType: meal.mealType,
      aiEstimate: stored.aiEstimate,
      current: meal.current,
      isEdited: meal.isEdited,
      createdAt: stored.createdAt,
      updatedAt: DateTime.now(),
    );
    _changes.add(_sorted());
  }

  @override
  Future<void> deleteMeal(String mealId) async {
    deleteCalls++;
    await _awaitGate();

    final MealRepositoryFailure? failure = deleteFailure;
    if (failure != null) throw failure;

    deletedIds.add(mealId);
    _meals.removeWhere((SavedMeal meal) => meal.id == mealId);
    _changes.add(_sorted());
  }

  /// Days passed to [mealsForDate], oldest call first, so a test can see
  /// exactly which days were read - and that nothing else was.
  final List<DateTime> datesRequested = <DateTime>[];

  @override
  Future<List<SavedMeal>> mealsForDate(DateTime day) async {
    datesRequested.add(DateTime(day.year, day.month, day.day));
    return mealsOnDay(_sorted(), day);
  }

  /// Spans passed to [mealsForRange], oldest call first, as the first and
  /// last local day asked for.
  final List<(DateTime, DateTime)> rangesRequested = <(DateTime, DateTime)>[];

  @override
  Future<List<SavedMeal>> mealsForRange(
    DateTime firstDay,
    DateTime lastDay,
  ) async {
    final DateTime first = Week.dayOf(firstDay);
    final DateTime last = Week.dayOf(lastDay);
    rangesRequested.add((first, last));

    // Both ends included, exactly as the real query reads them: midnight on
    // the first day up to midnight after the last. Deliberately through the
    // same `Week` helpers the real repository uses, so the two cannot end up
    // with different ideas of where a calendar day stops - which is how a
    // daylight-saving bug in the real one stayed invisible behind a fake that
    // happened to be right.
    final DateTime end = Week.addDays(last, 1);
    return _sorted()
        .where(
          (SavedMeal meal) =>
              !meal.createdAt.isBefore(first) && meal.createdAt.isBefore(end),
        )
        .toList();
  }

  /// How many times the cheap presence check was made.
  int hasAnyMealsCalls = 0;

  @override
  Future<bool> hasAnyMeals() async {
    hasAnyMealsCalls++;
    return _meals.isNotEmpty;
  }
}

/// An in-memory [ProfileRepository] for screen tests.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.storedProfile});

  /// The profile currently held, or null when the user has none.
  UserProfile? storedProfile;
  final StreamController<UserProfile?> _changes =
      StreamController<UserProfile?>.broadcast();

  /// Set to make every read and write fail, so error paths can be tested.
  ProfileRepositoryFailure? failure;

  int saveCalls = 0;
  int updateCalls = 0;
  int loadCalls = 0;

  void dispose() => _changes.close();

  @override
  Future<UserProfile?> getProfile() async {
    loadCalls++;
    final ProfileRepositoryFailure? error = failure;
    if (error != null) throw error;
    return storedProfile;
  }

  @override
  Stream<UserProfile?> watchProfile() async* {
    yield storedProfile;
    yield* _changes.stream;
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    saveCalls++;
    await _write(profile);
  }

  @override
  Future<void> updateProfile(UserProfile profile) async {
    updateCalls++;
    await _write(profile);
  }

  Future<void> _write(UserProfile profile) async {
    final ProfileRepositoryFailure? error = failure;
    if (error != null) throw error;
    storedProfile = profile;
    _changes.add(profile);
  }
}

/// A profile with sensible values, for tests that just need one.
UserProfile buildProfile({
  String name = 'Alex Carter',
  int age = 28,
  Gender gender = Gender.male,
  double heightCm = 175,
  double weightKg = 70,
  ActivityLevel activityLevel = ActivityLevel.moderate,
  NutritionGoal goal = NutritionGoal.maintain,
}) {
  return UserProfile(
    name: name,
    age: age,
    gender: gender,
    heightCm: heightCm,
    weightKg: weightKg,
    activityLevel: activityLevel,
    goal: goal,
  );
}
