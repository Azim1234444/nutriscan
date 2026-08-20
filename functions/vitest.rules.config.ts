import { defineConfig } from "vitest/config";

/**
 * The Firestore security rules suite, which only means anything when it runs
 * against an emulator.
 *
 * The suite is named here rather than filtered on the command line, so asking
 * for it is a structural fact this config can act on: `setupFiles` runs before
 * any test and refuses a run with no emulator behind it. That is what stops
 * this command reporting success on rules it did not check.
 */
export default defineConfig({
  test: {
    include: ["test/firestore-rules.test.ts"],
    setupFiles: ["test/require-emulator.ts"],
  },
});
