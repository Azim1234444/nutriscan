import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import 'nutriscan_app.dart';

typedef FirebaseInitializer = Future<void> Function();
typedef ReadyAppBuilder = Widget Function();

/// Point Firebase calls at the local emulators instead of production.
///
/// Debug builds only: release builds always talk to the real project, so
/// nothing here can affect production data.
const bool _useEmulators = kDebugMode;

/// Where the emulators are reachable from the running app.
///
/// Loopback on purpose. FlutterFire rewrites this per platform: on an Android
/// emulator it becomes 10.0.2.2, the alias for the host's own loopback, and
/// that is what the device actually dials - it logs the swap as `Mapping Auth
/// Emulator host "127.0.0.1" to "10.0.2.2"`. The tunnels below are belt and
/// braces for tooling that does no such rewriting; the app does not need them:
///
///   adb reverse tcp:5001 tcp:5001
///   adb reverse tcp:8080 tcp:8080
///   adb reverse tcp:9099 tcp:9099
///
/// One trap is worth knowing about, because it looks like a broken emulator
/// and is not. The Auth emulator holds its accounts in memory and loses them
/// when it restarts, while the app keeps its session on disk and restores it
/// without asking the server. A device can therefore be holding a session for
/// an account that no longer exists: reads go on working, because the
/// Firestore emulator does not check that the id belongs to anybody, and the
/// first call that genuinely needs the auth server - creating an account, for
/// instance - fails with "no user record" and signs the device out. Clear the
/// app's stored session whenever the emulators are restarted:
///
///   adb shell pm clear com.azim.nutriscan
const String _emulatorHost = '127.0.0.1';
const int _functionsEmulatorPort = 5001;
const int _firestoreEmulatorPort = 8080;
const int _authEmulatorPort = 9099;

/// Holds Firebase-dependent application construction behind initialization.
///
/// Tests can replace both callbacks. Production uses [_initializeFirebase]
/// and constructs [NutriScanApp] only after it completes successfully.
class FirebaseStartup extends StatefulWidget {
  const FirebaseStartup({super.key, this.initialize, this.readyAppBuilder});

  final FirebaseInitializer? initialize;
  final ReadyAppBuilder? readyAppBuilder;

  @override
  State<FirebaseStartup> createState() => _FirebaseStartupState();
}

enum _StartupState { initializing, failed, ready }

class _FirebaseStartupState extends State<FirebaseStartup> {
  _StartupState _state = _StartupState.initializing;
  Widget? _readyApp;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final int attempt = ++_attempt;

    try {
      await (widget.initialize ?? _initializeFirebase)();
      if (!mounted || attempt != _attempt) return;

      final Widget readyApp =
          widget.readyAppBuilder?.call() ?? const NutriScanApp();
      setState(() {
        _readyApp = readyApp;
        _state = _StartupState.ready;
      });
    } catch (error, stackTrace) {
      if (!mounted || attempt != _attempt) return;

      // Do not include the exception message: provider errors can contain
      // configuration or request details that do not belong in logs or UI.
      debugPrint(
        'Firebase startup failed during initialization '
        '(${error.runtimeType}).',
      );
      debugPrintStack(
        label: 'Firebase startup failure location',
        stackTrace: stackTrace,
      );

      setState(() {
        _readyApp = null;
        _state = _StartupState.failed;
      });
    }
  }

  void _retry() {
    if (_state == _StartupState.initializing) return;

    setState(() {
      _readyApp = null;
      _state = _StartupState.initializing;
    });
    unawaited(_initialize());
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _StartupState.ready) return _readyApp!;

    return MaterialApp(
      title: 'NutriScan',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _state == _StartupState.initializing
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.cloud_off_outlined, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'NutriScan couldn\'t start',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Check your connection and try again.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('firebase-startup-retry'),
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Initializes Firebase before any Firebase-dependent service is constructed.
Future<void> _initializeFirebase() async {
  // A failed later phase can leave the core app initialized. Reusing it makes
  // Retry safe while a core initialization failure still gets a fresh attempt.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (_useEmulators) {
    await _connectEmulators();
  }

  await _activateAppCheck();
}

Future<void> _connectEmulators() async {
  FirebaseFunctions.instance.useFunctionsEmulator(
    _emulatorHost,
    _functionsEmulatorPort,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    _emulatorHost,
    _firestoreEmulatorPort,
  );
  await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, _authEmulatorPort);
}

/// Attests that requests come from a genuine build of this app.
///
/// Debug builds use the debug provider, which needs its token registered once
/// in the Firebase console; release builds use Play Integrity. The token is
/// printed by the Firebase SDK itself - treat it as a credential, keep it out
/// of source control, and never paste it anywhere public.
///
/// The backend does not enforce App Check yet, so a failure here is logged
/// without a token value and the app carries on.
Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          // The debug token is generated by the SDK, never hard-coded here.
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (error) {
    debugPrint('App Check activation failed: ${error.runtimeType}');
  }
}
