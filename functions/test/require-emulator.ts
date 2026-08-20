/**
 * Refuses to run the security rules suite without an emulator to run it
 * against.
 *
 * A skipped suite is reported as a success: `vitest run` on the rules file
 * with nothing listening exits 0 having checked no rule at all, which is
 * exactly how a broken rule reaches production behind a green command.
 * Throwing here turns that silence into a failure, so the command that asks
 * for these tests either executes them or goes red.
 *
 * The address comes from the emulator itself - `firebase emulators:exec` sets
 * FIRESTORE_EMULATOR_HOST for whatever it runs - so no port is written down
 * here, and none can drift from the one in firebase.json.
 */
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    "Firestore emulator is required for rules tests. " +
      "Run `npm run test:rules`, which starts one, or point " +
      "FIRESTORE_EMULATOR_HOST at an emulator that is already running.",
  );
}
