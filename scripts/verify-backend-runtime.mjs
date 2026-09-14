import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { fileURLToPath } from "node:url";

const repositoryRoot = new URL("../", import.meta.url);
const outputDirectory = new URL(".backend-runtime/", repositoryRoot);

try {
  rmSync(outputDirectory, { force: true, recursive: true });
  execFileSync(
    process.execPath,
    [
      fileURLToPath(new URL("node_modules/typescript/bin/tsc", repositoryRoot)),
      "-p",
      fileURLToPath(new URL("tsconfig.runtime.json", repositoryRoot)),
    ],
    { stdio: "inherit" },
  );

  const module = await import(
    new URL("api/analyze-food.js", outputDirectory).href
  );
  if (typeof module.default?.fetch !== "function") {
    throw new Error("Compiled API does not export a fetch handler.");
  }

  console.log("Compiled Vercel API loaded successfully with Node ESM.");
} finally {
  rmSync(outputDirectory, { force: true, recursive: true });
}
