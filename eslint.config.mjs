import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["api/**/*.ts", "backend/**/*.ts", "backend-test/**/*.ts"],
    languageOptions: {
      globals: {
        console: "readonly",
        process: "readonly",
        Request: "readonly",
        Response: "readonly",
      },
    },
  },
  {
    files: ["scripts/**/*.mjs"],
    languageOptions: {
      globals: {
        console: "readonly",
        process: "readonly",
        URL: "readonly",
      },
    },
  },
);
