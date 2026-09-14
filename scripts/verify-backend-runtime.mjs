import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

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

  const firebaseApp = initializeApp(
    { projectId: "nutriscan-runtime-check" },
    "nutriscan-runtime-check",
  );
  try {
    const auth = getAuth(firebaseApp);
    if (auth.app !== firebaseApp) {
      throw new Error("Firebase Admin Auth initialized against the wrong app.");
    }
  } finally {
    await deleteApp(firebaseApp);
  }

  console.log(
    "Compiled Vercel API and Firebase Admin Auth loaded successfully with strict Node ESM.",
  );
} finally {
  rmSync(outputDirectory, { force: true, recursive: true });
}
