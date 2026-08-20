import 'package:flutter/material.dart';

import '../services/app_state.dart';

/// Makes the shared [AppState] available to every screen.
///
/// This is Flutter's built-in way to share state - no extra packages needed.
/// Read it from any widget with:
///
/// ```dart
/// final AppState state = AppScope.of(context);
/// ```
///
/// Widgets that call this rebuild whenever the state notifies its listeners.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found above this widget.');
    return scope!.notifier!;
  }
}
