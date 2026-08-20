import { defineConfig } from "vitest/config";

/**
 * The hermetic backend test run: everything that needs nothing but Node.
 *
 * The Firestore rules suite is deliberately left out rather than skipped. A
 * skipped suite still counts as a pass, so leaving it in would mean `npm test`
 * reporting green on rules it never ran. It has its own command instead -
 * `npm run test:rules`, configured by vitest.rules.config.ts - which starts an
 * emulator and fails without one.
 */
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    exclude: ["test/firestore-rules.test.ts", "node_modules/**", "lib/**"],
  },
});
