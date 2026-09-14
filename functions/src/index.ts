import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

import { handleAnalyzeFoodImage } from "./ai/analyze-food.js";
import { createGeminiClient } from "./ai/gemini-client.js";
import type { AnalyzeFoodImageResponse } from "./types/nutrition.js";

// 2nd generation defaults for every function in this codebase.
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

/** Gemini key binding retained for the existing callable backend. */
const geminiApiKey = defineSecret("GEMINI_API_KEY");

/** True while running under the Functions emulator. */
const runningInEmulator = process.env.FUNCTIONS_EMULATOR === "true";

/**
 * Whether callers must present a valid App Check token.
 *
 * App Check is wired up but not switched on yet: the Android provider still
 * has to be registered in the Firebase console, and turning this on before
 * that would lock the real app out. Enable it for a deployment with:
 *
 *   firebase deploy --only functions --set-env-vars APP_CHECK_ENFORCED=true
 *
 * The emulator never enforces, so local development keeps working either way.
 * Authentication is enforced regardless of this setting.
 */
const enforceAppCheck =
  process.env.APP_CHECK_ENFORCED === "true" && !runningInEmulator;

/**
 * Callable entry point for food photo analysis.
 *
 * The client sends `{ imageBase64, mimeType }` and never talks to Gemini
 * directly - the API key is bound here as a Secret Manager secret, read inside
 * the request, and stays on the server. Remote image URLs are not accepted;
 * only inline image bytes are.
 *
 * Callers must be signed in. The check lives in the handler so tests can drive
 * it directly, and it runs before any Gemini work is done.
 *
 * Replies with either `{ status: "ok", analysis }` or
 * `{ status: "no_food_detected", reason }`.
 */
export const analyzeFoodImage = onCall(
  {
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 60,
    enforceAppCheck,
  },
  (request: CallableRequest<unknown>): Promise<AnalyzeFoodImageResponse> =>
    handleAnalyzeFoodImage(
      { data: request.data, auth: request.auth },
      createGeminiClient(geminiApiKey.value()),
    ),
);
