import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/nutrition_summary.dart';
import '../models/saved_profile.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'nutrition_calculator.dart';

/// Raised when a profile cannot be read or written.
///
/// [message] is safe to show, and the caller can offer a retry.
class ProfileRepositoryFailure implements Exception {
  const ProfileRepositoryFailure(this.message);

  final String message;

  @override
  String toString() => 'ProfileRepositoryFailure: $message';
}

/// Reads and writes the signed-in user's nutrition profile.
///
/// Screens depend on this interface, never on Firestore directly.
abstract class ProfileRepository {
  /// The stored profile, or null when the user has not set one up.
  Future<UserProfile?> getProfile();

  /// The stored profile, updating as it changes.
  Stream<UserProfile?> watchProfile();

  /// Creates or replaces the profile.
  Future<void> saveProfile(UserProfile profile);

  /// Updates an existing profile, leaving `createdAt` as it was.
  Future<void> updateProfile(UserProfile profile);
}

/// [ProfileRepository] backed by Cloud Firestore.
///
/// The profile lives at `users/{uid}/profile/current`. Firestore paths
/// alternate collection and document, so `users/{uid}/profile` is a
/// collection: `current` is the single document inside it.
class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository({
    required AuthService authService,
    FirebaseFirestore? firestore,
  }) : _auth = authService,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final FirebaseFirestore _firestore;

  static const String usersCollection = 'users';
  static const String profileCollection = 'profile';

  /// The one document id used for a user's profile.
  static const String profileDocumentId = 'current';

  DocumentReference<Map<String, dynamic>> _profileRef(String userId) {
    return _firestore
        .collection(usersCollection)
        .doc(userId)
        .collection(profileCollection)
        .doc(profileDocumentId);
  }

  /// The signed-in user for work on a profile that already exists.
  ///
  /// An edit belongs to the account the profile was written under. Without
  /// that account there is nothing to edit, and starting a session here would
  /// only invent a different one, so this refuses instead.
  String _requireSession() {
    final String? userId = _auth.currentUserId;
    if (userId == null) {
      throw const ProfileRepositoryFailure(
        'You are signed out. Sign in to change your profile.',
      );
    }
    return userId;
  }

  @override
  Future<UserProfile?> getProfile() async {
    // `currentUserId`, never `ensureSignedIn`: reading a profile must not
    // bring an account into existence. Nobody signed in has no profile, and
    // saying so is what lets the app offer onboarding or sign-in instead of
    // silently starting a new, empty account.
    final String? userId = _auth.currentUserId;
    if (userId == null) return null;

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _profileRef(
        userId,
      ).get();

      return profileFromFirestore(snapshot.data());
    } on AuthFailure catch (error) {
      throw ProfileRepositoryFailure(error.message);
    } on FirebaseException catch (error) {
      throw ProfileRepositoryFailure(_messageFor(error.code, saving: false));
    } catch (_) {
      throw const ProfileRepositoryFailure(
        'Your profile could not be loaded. Please try again.',
      );
    }
  }

  @override
  Stream<UserProfile?> watchProfile() {
    // Watching is reading, so the same rule applies: no session means no
    // profile, not a new account.
    final String? userId = _auth.currentUserId;
    if (userId == null) return Stream<UserProfile?>.value(null);

    return _profileRef(userId).snapshots().map(
      (DocumentSnapshot<Map<String, dynamic>> snapshot) =>
          profileFromFirestore(snapshot.data()),
    );
  }

  @override
  Future<void> saveProfile(UserProfile profile) => _write(profile, isNew: true);

  @override
  Future<void> updateProfile(UserProfile profile) =>
      _write(profile, isNew: false);

  /// Writes the profile with freshly calculated targets.
  ///
  /// The numbers come from [NutritionCalculator] - the only place in the app
  /// that knows how to work them out.
  Future<void> _write(UserProfile profile, {required bool isNew}) async {
    try {
      // Saving a profile for the first time is the moment the app is meant to
      // start a session: it is the user's own deliberate act, and everything
      // they go on to save belongs to the account it creates. Editing a
      // profile that already exists is not that moment - it acts on an
      // account that must already be there - so it asks instead of creating.
      final String userId = isNew
          ? await _auth.ensureSignedIn()
          : _requireSession();
      final NutritionSummary targets = NutritionCalculator.targetsFor(profile);

      await _profileRef(userId).set(
        profileToFirestore(
          profile,
          uid: userId,
          dailyCalories: targets.calories,
          proteinGrams: targets.proteinG,
          carbohydratesGrams: targets.carbsG,
          fatGrams: targets.fatG,
          updatedAt: FieldValue.serverTimestamp(),
          // Only a create stamps createdAt; an update leaves the original.
          createdAt: isNew ? FieldValue.serverTimestamp() : null,
        ),
        SetOptions(merge: !isNew),
      );
    } on AuthFailure catch (error) {
      throw ProfileRepositoryFailure(error.message);
    } on FirebaseException catch (error) {
      throw ProfileRepositoryFailure(_messageFor(error.code, saving: true));
    } catch (_) {
      throw const ProfileRepositoryFailure(
        'Your profile could not be saved. Please try again.',
      );
    }
  }

  String _messageFor(String code, {required bool saving}) {
    switch (code) {
      case 'permission-denied':
        return 'You do not have access to this profile.';
      case 'unavailable':
      case 'network-request-failed':
        return 'No connection to the profile database. Please try again.';
      case 'deadline-exceeded':
        return 'The request took too long. Please try again.';
      default:
        return saving
            ? 'Your profile could not be saved. Please try again.'
            : 'Your profile could not be loaded. Please try again.';
    }
  }
}
