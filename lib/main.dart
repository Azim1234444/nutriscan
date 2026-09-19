import 'package:flutter/material.dart';

import 'app/firebase_startup.dart';

/// Entry point. Startup is gated before Firebase-dependent UI is built.
Future<void> main() async {
  // Required before any plugin is used ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const FirebaseStartup());
}
