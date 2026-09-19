import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, onCall } from "firebase-functions/v2/https";

import { handleAnalyzeFoodImage } from "./ai/analyze-food";
import { createGeminiClient, geminiApiKey } from "./ai/gemini-client";
import { AnalyzeFoodImageResponse } from "./types/nutrition";

// 2nd generation defaults shared by every function in this codebase.
setGlobalOptions({ region: "us-central1" });

/** True while running under the Functions emulator. */
const runningInEmulator = process.env.FUNCTIONS_EMULATOR === "true";

/**
 * Source-controlled production rollout switch for App Check enforcement.
 *
 * Keep this false while validating Play Integrity traffic in App Check metrics.
 * To enable enforcement later, first confirm that internal/closed Play builds
 * produce valid tokens, then intentionally change this to true and redeploy
 * only analyzeFoodImage. Recheck metrics and callable failures after rollout.
 * The emulator remains unenforced regardless of this switch. Authentication is
 * enforced independently in the request handler.
 */
const enforceAppCheckInProduction = false;
const enforceAppCheck = enforceAppCheckInProduction && !runningInEmulator;

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
    // Bound model traffic to six simultaneous calls (2 requests x 3 instances).
    concurrency: 2,
    maxInstances: 3,
    enforceAppCheck,
  },
  (request: CallableRequest<unknown>): Promise<AnalyzeFoodImageResponse> =>
    handleAnalyzeFoodImage(
      { data: request.data, auth: request.auth },
      createGeminiClient(geminiApiKey.value()),
    ),
);
