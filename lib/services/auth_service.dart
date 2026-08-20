import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Raised when the app cannot get a signed-in user.
///
/// [message] is safe to show: it never carries Firebase's internal wording.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// An [AuthFailure] that also left the device with no session at all.
///
/// Firebase ends the session when it discovers the account it was holding no
/// longer exists. Nothing stored is deleted - every document stays under the
/// id it was written with - but the app can no longer reach any of it, which
/// is a different situation from an attempt that simply did not work.
///
/// It is reported separately because it needs something different from the
/// user: not another go at the same button, but a way back in. Retrying a
/// link with no session would start a fresh anonymous account and quietly
/// leave the old one behind, which is the outcome this type exists to
/// prevent.
class AuthSessionLost extends AuthFailure {
  const AuthSessionLost(super.message);

  @override
  String toString() => 'AuthSessionLost: $message';
}

/// Signs the user in so their meals can be scoped to an account.
///
/// Phase 2D uses anonymous sign-in only: there is no login screen, and the
/// user never sees this happen. A real sign-in method can replace
/// [ensureSignedIn] later without touching the callers.
abstract class AuthService {
  /// Returns the current user id, signing in anonymously if needed.
  ///
  /// Throws [AuthFailure] when no user can be established.
  Future<String> ensureSignedIn();

  /// The signed-in user id, or null before the first sign-in.
  String? get currentUserId;

  /// Whether a session exists at all, of either kind.
  bool get isSignedIn;

  /// True while the session belongs to an anonymous, device-only account.
  ///
  /// Null before anyone is signed in.
  bool? get isAnonymous;

  /// Email on the current account, or null for an anonymous one.
  ///
  /// Shown so a signed-in user can see which account they are about to sign
  /// out of. The user id is deliberately not exposed.
  String? get currentUserEmail;

  /// Turns the current anonymous account into a permanent one.
  ///
  /// The account is *linked*, never replaced: the user keeps the same id, so
  /// their profile and meals stay exactly where they are. Returns the user id,
  /// which is the same one they had before.
  ///
  /// Throws [AuthFailure] when the account cannot be upgraded, or
  /// [AuthSessionLost] when the attempt also ended the session - which the
  /// caller has to handle differently, because there is then nothing left to
  /// retry against.
  Future<String> linkEmailPassword({
    required String email,
    required String password,
  });

  /// Signs in to an account that already exists.
  ///
  /// This is how a user gets back to their data on a new device or after the
  /// app's storage is cleared: authenticating returns the id the account was
  /// created with, so the profile and meals already stored under it are simply
  /// there again. Nothing is copied or migrated. Returns that user id.
  ///
  /// Throws [AuthFailure] when the credentials are not accepted.
  Future<String> signInWithEmailPassword({
    required String email,
    required String password,
  });

  /// Asks Firebase to email a password reset link.
  ///
  /// The new password is chosen on Firebase's own page, so the app never sees
  /// or handles it.
  ///
  /// Throws [AuthFailure] when the request cannot be sent.
  Future<void> sendPasswordResetEmail(String email);

  /// Ends the session.
  ///
  /// Authentication only: no Firestore document is touched and the Firebase
  /// account itself is left exactly as it is, so signing back in returns the
  /// user to everything they had. Callers are responsible for clearing what
  /// the app holds in memory.
  ///
  /// Throws [AuthFailure] when the session cannot be ended.
  Future<void> signOut();
}

/// [AuthService] backed by Firebase Authentication.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Guards against several screens asking to sign in at the same time.
  Future<String>? _pendingSignIn;

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  bool? get isAnonymous => _auth.currentUser?.isAnonymous;

  @override
  String? get currentUserEmail {
    final String? email = _auth.currentUser?.email;
    return (email == null || email.isEmpty) ? null : email;
  }

  @override
  Future<String> ensureSignedIn() {
    final User? user = _auth.currentUser;
    if (user != null) return Future<String>.value(user.uid);

    // Reuse the in-flight sign-in so two callers cannot create two users.
    return _pendingSignIn ??= _signInAnonymously().whenComplete(() {
      _pendingSignIn = null;
    });
  }

  Future<String> _signInAnonymously() async {
    try {
      final UserCredential credential = await _auth.signInAnonymously();
      final String? uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Could not start a session. Please try again.');
      }
      return uid;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messageFor(error.code));
    } on SocketException {
      throw const AuthFailure('No internet connection. Connect and try again.');
    } on TimeoutException {
      throw const AuthFailure('Signing in took too long. Please try again.');
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Could not start a session. Please try again.');
    }
  }

  /// Maps a Firebase error code to wording a user can act on.
  String _messageFor(String code) {
    switch (code) {
      case 'operation-not-allowed':
        // Anonymous sign-in is switched off in the Firebase console.
        return 'Sign-in is unavailable right now. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Connect and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Could not start a session. Please try again.';
    }
  }

  @override
  Future<String> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    // Linking works on the account that is already signed in, so make sure
    // there is one before building any credential.
    final String userId = await ensureSignedIn();
    final User? user = _auth.currentUser;

    if (user == null) {
      throw const AuthFailure('Could not start a session. Please try again.');
    }
    if (!user.isAnonymous) {
      throw const AuthFailure('This device already has a saved account.');
    }

    try {
      final UserCredential credential = await user.linkWithCredential(
        EmailAuthProvider.credential(email: email.trim(), password: password),
      );

      final String? linkedId = credential.user?.uid;
      // The whole point of linking: the id must survive unchanged, because
      // every profile and meal document is stored under it.
      if (linkedId == null || linkedId != userId) {
        throw const AuthFailure(
          'The account could not be saved. Please try again.',
        );
      }
      return linkedId;
    } on FirebaseAuthException catch (error) {
      // Only the code is used - Firebase's own wording never reaches the user,
      // and the password is never part of any message.
      throw _linkFailure(_linkMessageFor(error.code));
    } on SocketException {
      throw _linkFailure('No internet connection. Connect and try again.');
    } on TimeoutException {
      throw _linkFailure('That took too long. Please try again.');
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw _linkFailure('The account could not be saved. Please try again.');
    }
  }

  /// Describes a link that did not happen, and says whether the session
  /// survived it.
  ///
  /// Firebase ends the session when it finds the account it was holding no
  /// longer exists, so whether there is still an account to go back to is a
  /// question about this particular attempt, not about the error code. It is
  /// asked here rather than assumed: the answer decides whether the user is
  /// offered another go or a way back in.
  AuthFailure _linkFailure(String message) {
    if (_auth.currentUser != null) return AuthFailure(message);

    return const AuthSessionLost(
      'The account could not be created, and this device has been signed out. '
      'Nothing has been deleted. Sign in if you already have an account.',
    );
  }

  /// Maps a linking error code to wording a user can act on.
  String _linkMessageFor(String code) {
    switch (code) {
      case 'email-already-in-use':
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return 'That email is already used by another account. '
            'Try a different one.';
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'weak-password':
        return 'Choose a stronger password of at least 8 characters.';
      case 'provider-already-linked':
        return 'This device already has a saved account.';
      case 'operation-not-allowed':
        return 'Creating an account is unavailable right now. '
            'Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Connect and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'requires-recent-login':
        return 'Please restart the app and try again.';
      default:
        return 'The account could not be saved. Please try again.';
    }
  }

  @override
  Future<String> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final String? userId = credential.user?.uid;
      if (userId == null) {
        throw const AuthFailure('Could not sign you in. Please try again.');
      }
      // The id comes from the account that already existed, so every document
      // stored under it is reachable again without moving anything.
      return userId;
    } on FirebaseAuthException catch (error) {
      // Only the code is read: Firebase's own wording, and anything the user
      // typed, stay out of the message.
      throw AuthFailure(_signInMessageFor(error.code));
    } on SocketException {
      throw const AuthFailure('No internet connection. Connect and try again.');
    } on TimeoutException {
      throw const AuthFailure('That took too long. Please try again.');
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Could not sign you in. Please try again.');
    }
  }

  /// Maps a sign-in error code to wording a user can act on.
  ///
  /// A wrong password and an unknown email deliberately share one message:
  /// telling them apart would let anyone test which addresses have accounts.
  String _signInMessageFor(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'That email or password is not right. Please try again.';
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Connect and try again.';
      case 'operation-not-allowed':
        return 'Signing in is unavailable right now. Please try again later.';
      default:
        return 'Could not sign you in. Please try again.';
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // An address with no account is not reported as a failure: saying so
      // would reveal who has an account here. The caller shows the same
      // "check your inbox" message either way.
      if (error.code == 'user-not-found') return;
      throw AuthFailure(_resetMessageFor(error.code));
    } on SocketException {
      throw const AuthFailure('No internet connection. Connect and try again.');
    } on TimeoutException {
      throw const AuthFailure('That took too long. Please try again.');
    } catch (_) {
      throw const AuthFailure(
        'The reset email could not be sent. Please try again.',
      );
    }
  }

  /// Maps a reset error code to wording a user can act on.
  String _resetMessageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Connect and try again.';
      case 'operation-not-allowed':
        return 'Password reset is unavailable right now. '
            'Please try again later.';
      default:
        return 'The reset email could not be sent. Please try again.';
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_signOutMessageFor(error.code));
    } on SocketException {
      throw const AuthFailure('No internet connection. Connect and try again.');
    } on TimeoutException {
      throw const AuthFailure('That took too long. Please try again.');
    } catch (_) {
      throw const AuthFailure('Could not sign out. Please try again.');
    }
  }

  /// Maps a sign-out error code to wording a user can act on.
  String _signOutMessageFor(String code) {
    switch (code) {
      case 'network-request-failed':
        return 'No internet connection. Connect and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Could not sign out. Please try again.';
    }
  }
}
