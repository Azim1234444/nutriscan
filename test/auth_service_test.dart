// Tests for anonymous sign-in.
//
// FirebaseAuth is faked through its implicit interface, so these run without
// Firebase, a network or an emulator.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutriscan/services/auth_service.dart';

/// Signs in successfully and remembers the user, like the real SDK.
class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth({this.errorCode});

  /// When set, `signInAnonymously` throws with this code.
  final String? errorCode;

  int signInCalls = 0;
  User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Future<UserCredential> signInAnonymously() async {
    signInCalls++;
    final String? code = errorCode;
    if (code != null) {
      throw FirebaseAuthException(code: code);
    }
    final _FakeUser user = _FakeUser('anon-uid-$signInCalls');
    _currentUser = user;
    return _FakeUserCredential(user);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  // Everything else is unused by AuthService.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  _FakeUser(this.uid);

  @override
  final String uid;

  @override
  bool get isAnonymous => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserCredential implements UserCredential {
  _FakeUserCredential(this.user);

  @override
  final User? user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A credential with no user, which the SDK allows in principle.
class _EmptyUserCredential implements UserCredential {
  @override
  User? get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoUserFirebaseAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Future<UserCredential> signInAnonymously() async => _EmptyUserCredential();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _linkingTests();
  _linkErrorTests();
  _signInTests();
  _signInErrorTests();
  _resetTests();

  group('anonymous sign-in succeeds', () {
    test('returns a user id and remembers it', () async {
      final _FakeFirebaseAuth auth = _FakeFirebaseAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      expect(service.currentUserId, isNull);

      final String userId = await service.ensureSignedIn();

      expect(userId, isNotEmpty);
      expect(service.currentUserId, userId);
      expect(auth.signInCalls, 1);
    });

    test('reuses the existing user instead of creating another', () async {
      final _FakeFirebaseAuth auth = _FakeFirebaseAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      final String first = await service.ensureSignedIn();
      final String second = await service.ensureSignedIn();

      expect(second, first);
      expect(auth.signInCalls, 1);
    });

    test('two callers at once share one sign-in', () async {
      final _FakeFirebaseAuth auth = _FakeFirebaseAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      final List<String> ids = await Future.wait(<Future<String>>[
        service.ensureSignedIn(),
        service.ensureSignedIn(),
      ]);

      expect(ids.first, ids.last);
      expect(auth.signInCalls, 1);
    });

    test('signOut clears the session', () async {
      final _FakeFirebaseAuth auth = _FakeFirebaseAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      await service.ensureSignedIn();
      await service.signOut();

      expect(service.currentUserId, isNull);
    });
  });

  group('auth failures are reported safely', () {
    test('anonymous sign-in disabled in the console', () async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _FakeFirebaseAuth(errorCode: 'operation-not-allowed'),
      );

      await expectLater(
        service.ensureSignedIn(),
        throwsA(
          isA<AuthFailure>().having(
            (AuthFailure error) => error.message,
            'message',
            'Sign-in is unavailable right now. Please try again later.',
          ),
        ),
      );
    });

    test('a network failure asks the user to reconnect', () async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _FakeFirebaseAuth(errorCode: 'network-request-failed'),
      );

      await expectLater(
        service.ensureSignedIn(),
        throwsA(
          isA<AuthFailure>().having(
            (AuthFailure error) => error.message,
            'message',
            'No internet connection. Connect and try again.',
          ),
        ),
      );
    });

    test('an unknown code never leaks Firebase wording', () async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _FakeFirebaseAuth(errorCode: 'internal-error-abc'),
      );

      try {
        await service.ensureSignedIn();
        fail('Expected sign-in to fail');
      } on AuthFailure catch (error) {
        expect(error.message, 'Could not start a session. Please try again.');
        expect(error.message, isNot(contains('internal-error-abc')));
      }
    });

    test('a credential without a user is treated as a failure', () async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _NoUserFirebaseAuth(),
      );

      await expectLater(service.ensureSignedIn(), throwsA(isA<AuthFailure>()));
    });

    test('a failed attempt can be retried', () async {
      final _FakeFirebaseAuth auth = _FakeFirebaseAuth(
        errorCode: 'too-many-requests',
      );
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      await expectLater(service.ensureSignedIn(), throwsA(isA<AuthFailure>()));
      // The in-flight guard must not block a later attempt.
      await expectLater(service.ensureSignedIn(), throwsA(isA<AuthFailure>()));
      expect(auth.signInCalls, 2);
    });
  });
}

/// An anonymous user that can be linked, like the real SDK.
class _LinkableUser implements User {
  _LinkableUser(this.uid, {this.linkErrorCode, this.linkedUid, this.onFailure});

  @override
  final String uid;

  /// When set, linking throws with this code.
  final String? linkErrorCode;

  /// Id the credential comes back with; defaults to [uid].
  final String? linkedUid;

  /// Run when a link attempt fails.
  ///
  /// Firebase ends the session when it finds the account it was holding has
  /// gone - `user-not-found` on a link is one way there - so a fake needs a
  /// way to do the same, or the app's handling of it cannot be tested.
  final void Function()? onFailure;

  @override
  bool isAnonymous = true;

  int linkCalls = 0;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    linkCalls++;
    final String? code = linkErrorCode;
    if (code != null) {
      onFailure?.call();
      throw FirebaseAuthException(code: code);
    }

    isAnonymous = false;
    final _FakeUser linked = _FakeUser(linkedUid ?? uid);
    return _FakeUserCredential(linked);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A FirebaseAuth already holding a signed-in user.
class _SignedInAuth implements FirebaseAuth {
  _SignedInAuth(this._user);

  User? _user;
  int signInCalls = 0;

  @override
  User? get currentUser => _user;

  /// Drops the session, as Firebase does when the account it was holding
  /// turns out to be gone.
  void endSession() => _user = null;

  @override
  Future<UserCredential> signInAnonymously() async {
    signInCalls++;
    return _FakeUserCredential(_user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _linkingTests() {
  group('account linking', () {
    test('1 and 2. reports whether the session is anonymous', () async {
      final _LinkableUser anonymous = _LinkableUser('uid-1');
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _SignedInAuth(anonymous),
      );
      expect(service.isAnonymous, isTrue);

      await service.linkEmailPassword(
        email: 'alex@example.com',
        password: 'sunflower99',
      );

      expect(service.isAnonymous, isFalse);
    });

    test('3 and 4. linking keeps the same user id', () async {
      final _LinkableUser anonymous = _LinkableUser('uid-keep-me');
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _SignedInAuth(anonymous),
      );
      final String? before = service.currentUserId;

      final String linked = await service.linkEmailPassword(
        email: 'alex@example.com',
        password: 'sunflower99',
      );

      expect(linked, 'uid-keep-me');
      expect(linked, before);
      expect(anonymous.linkCalls, 1);
    });

    test('18. a linked account is never swapped for a different one', () async {
      // A backend that returns a different id would mean a second user, so
      // the service refuses the result instead of accepting it.
      final _LinkableUser anonymous = _LinkableUser(
        'uid-original',
        linkedUid: 'uid-somebody-else',
      );
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _SignedInAuth(anonymous),
      );

      await expectLater(
        service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('refuses to link an account that is already permanent', () async {
      final _LinkableUser user = _LinkableUser('uid-1')..isAnonymous = false;
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _SignedInAuth(user),
      );

      await expectLater(
        service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(
          isA<AuthFailure>().having(
            (AuthFailure error) => error.message,
            'message',
            'This device already has a saved account.',
          ),
        ),
      );
      expect(user.linkCalls, 0);
    });
  });
}

void _linkErrorTests() {
  group('linking failures are reported safely', () {
    /// Runs a link that fails with [code] and returns the message shown.
    Future<String> messageFor(String code) async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _SignedInAuth(_LinkableUser('uid-1', linkErrorCode: code)),
      );
      try {
        await service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        );
        fail('Expected linking to fail');
      } on AuthFailure catch (error) {
        return error.message;
      }
    }

    test('11. an email already in use is explained plainly', () async {
      expect(
        await messageFor('email-already-in-use'),
        'That email is already used by another account. Try a different one.',
      );
    });

    test('12. a credential already in use is explained plainly', () async {
      expect(
        await messageFor('credential-already-in-use'),
        'That email is already used by another account. Try a different one.',
      );
    });

    test('13. a network failure asks the user to reconnect', () async {
      expect(
        await messageFor('network-request-failed'),
        'No internet connection. Connect and try again.',
      );
    });

    test('other Firebase codes map to safe wording', () async {
      expect(
        await messageFor('invalid-email'),
        'That email address does not look right.',
      );
      expect(
        await messageFor('weak-password'),
        'Choose a stronger password of at least 8 characters.',
      );
      expect(
        await messageFor('provider-already-linked'),
        'This device already has a saved account.',
      );
      expect(
        await messageFor('operation-not-allowed'),
        'Creating an account is unavailable right now. Please try again later.',
      );
      expect(
        await messageFor('too-many-requests'),
        'Too many attempts. Please wait a moment and try again.',
      );
    });

    test(
      'an unknown code never leaks Firebase wording or the password',
      () async {
        final String message = await messageFor('internal-error-xyz');

        expect(message, 'The account could not be saved. Please try again.');
        expect(message, isNot(contains('internal-error-xyz')));
        expect(message, isNot(contains('sunflower99')));
      },
    );

    test('a failure that spares the session is an ordinary failure', () async {
      final _SignedInAuth auth = _SignedInAuth(
        _LinkableUser('uid-1', linkErrorCode: 'email-already-in-use'),
      );
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      await expectLater(
        service.linkEmailPassword(
          email: 'taken@example.com',
          password: 'sunflower99',
        ),
        // Not the session-lost kind: there is still an account to try again
        // against, and the screen should go on offering that.
        throwsA(isA<AuthFailure>().having(
          (AuthFailure error) => error is AuthSessionLost,
          'is AuthSessionLost',
          isFalse,
        )),
      );

      expect(service.currentUserId, 'uid-1');
      expect(service.isSignedIn, isTrue);
    });
  });

  group('a failed link that also ends the session', () {
    /// A link that fails the way Firebase fails when the account it was
    /// holding has gone: the attempt throws *and* the session is dropped.
    ({_SignedInAuth auth, FirebaseAuthService service}) losingSession() {
      late final _SignedInAuth auth;
      final _LinkableUser user = _LinkableUser(
        'uid-stranded',
        linkErrorCode: 'user-not-found',
        onFailure: () => auth.endSession(),
      );
      auth = _SignedInAuth(user);
      return (auth: auth, service: FirebaseAuthService(auth: auth));
    }

    test('G. it is reported as a lost session, not a retryable slip', () async {
      final service = losingSession().service;

      await expectLater(
        service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthSessionLost>()),
      );
    });

    test('G. the session really is gone afterwards', () async {
      final service = losingSession().service;

      await expectLater(
        service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthSessionLost>()),
      );

      expect(service.currentUserId, isNull);
      expect(service.isSignedIn, isFalse);
    });

    test('H. no replacement account is created to paper over it', () async {
      final ({_SignedInAuth auth, FirebaseAuthService service}) pair =
          losingSession();

      await expectLater(
        pair.service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthSessionLost>()),
      );

      // The whole point: a lost session is left visible rather than hidden
      // behind a new, empty anonymous account.
      expect(pair.auth.signInCalls, 0);
      expect(pair.service.currentUserId, isNull);
    });

    test('the message says nothing was deleted and never quotes Firebase',
        () async {
      final service = losingSession().service;

      try {
        await service.linkEmailPassword(
          email: 'alex@example.com',
          password: 'sunflower99',
        );
        fail('Expected the link to fail');
      } on AuthSessionLost catch (error) {
        expect(error.message, contains('Nothing has been deleted'));
        expect(error.message, contains('Sign in'));
        expect(error.message, isNot(contains('user-not-found')));
        expect(error.message, isNot(contains('sunflower99')));
      }
    });
  });
}

/// A user whose account is permanent, as sign-in would return.
class _PermanentUser implements User {
  _PermanentUser(this.uid);

  @override
  final String uid;

  @override
  bool get isAnonymous => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A FirebaseAuth that handles email/password sign-in and reset.
///
/// Failures carry deliberately recognisable Firebase wording so the tests can
/// prove none of it reaches the user.
class _EmailPasswordAuth implements FirebaseAuth {
  _EmailPasswordAuth({
    this.uid = 'uid-existing',
    this.errorCode,
    this.returnsNoUser = false,
  });

  /// Id of the account being signed in to.
  final String uid;

  /// When set, both sign-in and reset throw with this code.
  final String? errorCode;

  /// Models a credential that carries no user at all.
  final bool returnsNoUser;

  int signInCalls = 0;
  int resetCalls = 0;
  String? lastEmail;
  String? lastResetEmail;

  @override
  User? get currentUser => null;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    lastEmail = email;

    final String? code = errorCode;
    if (code != null) {
      throw FirebaseAuthException(
        code: code,
        message: 'FIREBASE-INTERNAL: $code for identifier',
      );
    }
    if (returnsNoUser) return _EmptyUserCredential();
    return _FakeUserCredential(_PermanentUser(uid));
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    resetCalls++;
    lastResetEmail = email;

    final String? code = errorCode;
    if (code != null) {
      throw FirebaseAuthException(
        code: code,
        message: 'FIREBASE-INTERNAL: $code for identifier',
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _signInTests() {
  group('signing in to an existing account', () {
    test('4 and 8. returns the id the account already had', () async {
      final _EmailPasswordAuth auth = _EmailPasswordAuth(uid: 'uid-from-2g');
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      final String userId = await service.signInWithEmailPassword(
        email: 'alex.carter@example.com',
        password: 'sunflower99',
      );

      // Recovering an account means adopting its id, not minting a new one.
      expect(userId, 'uid-from-2g');
      expect(auth.signInCalls, 1);
    });

    test('a stray space around the email does not stop sign-in', () async {
      final _EmailPasswordAuth auth = _EmailPasswordAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      await service.signInWithEmailPassword(
        email: '  alex.carter@example.com  ',
        password: 'sunflower99',
      );

      expect(auth.lastEmail, 'alex.carter@example.com');
    });

    test('sign-in never creates an account', () async {
      // `createUserWithEmailAndPassword` is not implemented on the fake, so a
      // call to it would fail this test loudly rather than quietly passing.
      final _EmailPasswordAuth auth = _EmailPasswordAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      await service.signInWithEmailPassword(
        email: 'alex.carter@example.com',
        password: 'sunflower99',
      );

      expect(auth.signInCalls, 1);
    });

    test('a credential without a user is treated as a failure', () async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _EmailPasswordAuth(returnsNoUser: true),
      );

      await expectLater(
        service.signInWithEmailPassword(
          email: 'alex.carter@example.com',
          password: 'sunflower99',
        ),
        throwsA(isA<AuthFailure>()),
      );
    });
  });
}

void _signInErrorTests() {
  group('sign-in failures are reported safely', () {
    /// Runs a sign-in that fails with [code] and returns the message shown.
    Future<String> messageFor(String code) async {
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _EmailPasswordAuth(errorCode: code),
      );
      try {
        await service.signInWithEmailPassword(
          email: 'alex.carter@example.com',
          password: 'sunflower99',
        );
        fail('Expected signing in to fail');
      } on AuthFailure catch (error) {
        return error.message;
      }
    }

    test('5. wrong credentials are explained without saying which', () async {
      const String expected =
          'That email or password is not right. Please try again.';

      // A wrong password and an unknown address share one message on purpose:
      // telling them apart would reveal which addresses have accounts.
      expect(await messageFor('invalid-credential'), expected);
      expect(await messageFor('wrong-password'), expected);
      expect(await messageFor('user-not-found'), expected);
    });

    test('other codes map to safe wording', () async {
      expect(
        await messageFor('invalid-email'),
        'That email address does not look right.',
      );
      expect(
        await messageFor('user-disabled'),
        'This account has been disabled.',
      );
      expect(
        await messageFor('too-many-requests'),
        'Too many attempts. Please wait a moment and try again.',
      );
      expect(
        await messageFor('network-request-failed'),
        'No internet connection. Connect and try again.',
      );
      expect(
        await messageFor('operation-not-allowed'),
        'Signing in is unavailable right now. Please try again later.',
      );
    });

    test('6. raw Firebase wording and the password never leak', () async {
      for (final String code in <String>[
        'invalid-credential',
        'wrong-password',
        'user-not-found',
        'invalid-email',
        'user-disabled',
        'too-many-requests',
        'network-request-failed',
        'operation-not-allowed',
        'internal-error-zzz',
      ]) {
        final String message = await messageFor(code);

        expect(message, isNot(contains('FIREBASE-INTERNAL')));
        expect(message, isNot(contains(code)));
        expect(message, isNot(contains('sunflower99')));
        expect(message, isNot(contains('alex.carter@example.com')));
      }
    });

    test('an unknown code falls back to safe wording', () async {
      expect(
        await messageFor('internal-error-zzz'),
        'Could not sign you in. Please try again.',
      );
    });
  });
}

void _resetTests() {
  group('password reset', () {
    test('11. sends the reset email for a trimmed address', () async {
      final _EmailPasswordAuth auth = _EmailPasswordAuth();
      final FirebaseAuthService service = FirebaseAuthService(auth: auth);

      await service.sendPasswordResetEmail('  alex.carter@example.com ');

      expect(auth.resetCalls, 1);
      expect(auth.lastResetEmail, 'alex.carter@example.com');
    });

    test('an unknown address is not reported as a failure', () async {
      // Saying "no such account" would let anyone check who is registered.
      final FirebaseAuthService service = FirebaseAuthService(
        auth: _EmailPasswordAuth(errorCode: 'user-not-found'),
      );

      await service.sendPasswordResetEmail('nobody@example.com');
    });

    test('13. failures are explained without Firebase wording', () async {
      Future<String> messageFor(String code) async {
        final FirebaseAuthService service = FirebaseAuthService(
          auth: _EmailPasswordAuth(errorCode: code),
        );
        try {
          await service.sendPasswordResetEmail('alex.carter@example.com');
          fail('Expected the reset to fail');
        } on AuthFailure catch (error) {
          return error.message;
        }
      }

      expect(
        await messageFor('invalid-email'),
        'That email address does not look right.',
      );
      expect(
        await messageFor('too-many-requests'),
        'Too many attempts. Please wait a moment and try again.',
      );
      expect(
        await messageFor('network-request-failed'),
        'No internet connection. Connect and try again.',
      );
      expect(
        await messageFor('operation-not-allowed'),
        'Password reset is unavailable right now. Please try again later.',
      );

      final String unknown = await messageFor('internal-error-zzz');
      expect(unknown, 'The reset email could not be sent. Please try again.');
      expect(unknown, isNot(contains('FIREBASE-INTERNAL')));
      expect(unknown, isNot(contains('internal-error-zzz')));
    });
  });
}
