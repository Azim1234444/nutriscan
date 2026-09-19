import { describe, expect, it } from "vitest";

import { analyzeFoodImage } from "../src";

describe("analyzeFoodImage runtime configuration", () => {
  it("keeps the reviewed deployment and Gemini request limits", () => {
    expect(analyzeFoodImage.__endpoint).toMatchObject({
      availableMemoryMb: 512,
      timeoutSeconds: 60,
      maxInstances: 3,
      concurrency: 2,
      platform: "gcfv2",
      region: ["us-central1"],
      secretEnvironmentVariables: [{ key: "GEMINI_API_KEY" }],
      callableTrigger: {},
    });

    // firebase-functions omits a false value from the generated manifest;
    // absent therefore means enforcement is disabled, not unspecified.
    const callableTrigger = analyzeFoodImage.__endpoint.callableTrigger as
      | { enforceAppCheck?: boolean }
      | undefined;
    expect(callableTrigger?.enforceAppCheck ?? false).toBe(false);
  });
});
