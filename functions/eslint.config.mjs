import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: ["lib/**", "node_modules/**", "eslint.config.mjs"],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      quotes: ["error", "double", { avoidEscape: true }],
      "object-curly-spacing": ["error", "always"],
      // Backend code must never print secrets or image payloads; use the
      // firebase-functions logger instead of console.
      "no-console": "error",
    },
  },
);
