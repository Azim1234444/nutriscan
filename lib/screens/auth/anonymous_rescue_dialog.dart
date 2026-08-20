import 'package:flutter/material.dart';

import '../../services/anonymous_data.dart';

/// What the user decided when told their temporary data will not follow them.
enum RescueChoice {
  /// Upgrade this account first, keeping everything (the Phase 2G flow).
  createAccount,

  /// Switch anyway, leaving the temporary account's data where it is.
  signInAnyway,

  /// Stay put.
  cancel,
}

/// Explains what happens to a temporary account's data before switching away.
///
/// Signing in to another account is not destructive - nothing is deleted, and
/// the documents stay exactly where they are - but they stay under an id with
/// no email attached, so they cannot be reached again. That is easy to walk
/// into by accident, so the safe route is offered first and named plainly.
///
/// Returns null if the dialog is dismissed, which is treated as [cancel].
Future<RescueChoice?> showAnonymousRescueDialog(
  BuildContext context, {
  required AnonymousData data,
}) {
  return showDialog<RescueChoice>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Protect your NutriScan data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_whatIsSaved(data)),
            const SizedBox(height: 12),
            // Deliberately not "will be deleted": it will not be. Say what
            // actually happens instead.
            const Text(
              'If you sign in to another account, this temporary data stays '
              'with the temporary account and will not follow you.',
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(RescueChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(RescueChoice.signInAnyway),
            child: const Text('Sign in anyway'),
          ),
          // The recommended way out, so it is the emphasised one.
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(RescueChoice.createAccount),
            child: const Text('Create an account'),
          ),
        ],
      );
    },
  );
}

/// Names what is actually at stake, rather than warning in the abstract.
String _whatIsSaved(AnonymousData data) {
  if (data.hasProfile && data.hasMeals) {
    return 'Your profile and saved meals are on a temporary account. '
        'Creating an account keeps them, on the same account, with nothing '
        'to move.';
  }
  if (data.hasMeals) {
    return 'Your saved meals are on a temporary account. Creating an account '
        'keeps them, on the same account, with nothing to move.';
  }
  return 'Your profile is saved on a temporary account. Creating an account '
      'keeps it, on the same account, with nothing to move.';
}
