import { describe, expect, it } from "vitest";
import { HttpsError } from "firebase-functions/v2/https";

import {
  decodedSizeInBytes,
  handleAnalyzeFoodImage,
  validateAnalyzeFoodImageRequest,
} from "../src/ai/analyze-food";
import {
  FoodImage,
  GeminiClient,
  GeminiError,
  createGeminiClient,
} from "../src/ai/gemini-client";
import { MAX_IMAGE_BYTES } from "../src/types/nutrition";

/** A short but structurally valid base64 payload. */
const VALID_BASE64 = Buffer.from("pretend-jpeg-bytes").toString("base64");

const VALID_REQUEST = {
  imageBase64: VALID_BASE64,
  mimeType: "image/jpeg",
};

/** Model output for a photo of a real meal. */
const FOOD_RESPONSE = {
  food_detected: true,
  no_food_reason: "",
  food_name: "Grilled chicken salad",
  description: "A plate of mixed leaves with sliced grilled chicken breast.",
  estimated_portion_grams: 320,
  calories: 465,
  protein_grams: 42,
  carbohydrates_grams: 18,
  fat_grams: 24,
  fiber_grams: 6,
  confidence: 0.78,
  assumptions: ["Dressing assumed to be olive oil based."],
  items: [
    { name: "Grilled chicken breast", estimated_portion_grams: 150 },
    { name: "Mixed leaves", estimated_portion_grams: 120 },
  ],
};

/** Wraps request data as a call from a signed-in user. */
function signedInCall(data: unknown) {
  return { data, auth: { uid: "test-user" } };
}

/** Returns a canned result, or throws one, instead of calling Gemini. */
class MockGeminiClient implements GeminiClient {
  calls: FoodImage[] = [];

  constructor(private readonly outcome: { value?: unknown; error?: Error }) {}

  analyzeFoodImage(image: FoodImage): Promise<unknown> {
    this.calls.push(image);
    if (this.outcome.error) return Promise.reject(this.outcome.error);
    return Promise.resolve(this.outcome.value);
  }
}

function respondingWith(value: unknown): MockGeminiClient {
  return new MockGeminiClient({ value });
}

function failingWith(error: Error): MockGeminiClient {
  return new MockGeminiClient({ error });
}

/**
 * Builds a base64 string that decodes to exactly [bytes] bytes, padding
 * included, so the size limit can be tested to the byte.
 */
function base64OfSize(bytes: number): string {
  const groups = Math.ceil(bytes / 3);
  const padding = groups * 3 - bytes;
  return "A".repeat(groups * 4 - padding) + "=".repeat(padding);
}

/** Asserts the request was rejected as `invalid-argument`. */
function expectRejected(run: () => unknown): HttpsError {
  try {
    run();
  } catch (error) {
    expect(error).toBeInstanceOf(HttpsError);
    const httpsError = error as HttpsError;
    expect(httpsError.code).toBe("invalid-argument");
    return httpsError;
  }
  throw new Error("Expected the request to be rejected, but it was accepted.");
}

/** Asserts the call failed with the given callable error code. */
async function expectFailure(
  run: () => Promise<unknown>,
  code: string,
): Promise<HttpsError> {
  try {
    await run();
  } catch (error) {
    expect(error).toBeInstanceOf(HttpsError);
    const httpsError = error as HttpsError;
    expect(httpsError.code).toBe(code);
    return httpsError;
  }
  throw new Error("Expected the call to fail, but it succeeded.");
}

describe("validateAnalyzeFoodImageRequest", () => {
  it("accepts a valid request for every supported mime type", () => {
    for (const mimeType of ["image/jpeg", "image/png", "image/webp"]) {
      const result = validateAnalyzeFoodImageRequest({
        imageBase64: VALID_BASE64,
        mimeType,
      });

      expect(result.imageBase64).toBe(VALID_BASE64);
      expect(result.mimeType).toBe(mimeType);
    }
  });

  it("rejects a missing imageBase64", () => {
    const error = expectRejected(() =>
      validateAnalyzeFoodImageRequest({ mimeType: "image/jpeg" }),
    );
    expect(error.message).toContain("imageBase64");
  });

  it("rejects an empty imageBase64", () => {
    expectRejected(() =>
      validateAnalyzeFoodImageRequest({
        imageBase64: "",
        mimeType: "image/jpeg",
      }),
    );
    expectRejected(() =>
      validateAnalyzeFoodImageRequest({
        imageBase64: "   ",
        mimeType: "image/jpeg",
      }),
    );
  });

  it("rejects unsupported mime types", () => {
    for (const mimeType of ["image/gif", "application/pdf", "text/plain", ""]) {
      expectRejected(() =>
        validateAnalyzeFoodImageRequest({
          imageBase64: VALID_BASE64,
          mimeType,
        }),
      );
    }
  });

  it("rejects malformed requests", () => {
    const malformed: unknown[] = [
      undefined,
      null,
      "not-an-object",
      42,
      [],
      { imageBase64: 123, mimeType: "image/jpeg" },
      { imageBase64: VALID_BASE64 },
      {
        imageBase64: `data:image/jpeg;base64,${VALID_BASE64}`,
        mimeType: "image/jpeg",
      },
      { imageBase64: "not base64!!", mimeType: "image/png" },
    ];

    for (const request of malformed) {
      expectRejected(() => validateAnalyzeFoodImageRequest(request));
    }
  });

  it("rejects an oversized image", () => {
    const tooLarge = base64OfSize(MAX_IMAGE_BYTES + 1);

    expect(decodedSizeInBytes(tooLarge)).toBe(MAX_IMAGE_BYTES + 1);
    const error = expectRejected(() =>
      validateAnalyzeFoodImageRequest({
        imageBase64: tooLarge,
        mimeType: "image/jpeg",
      }),
    );
    expect(error.message).toContain("too large");
  });

  it("accepts an image right at the size limit", () => {
    const atLimit = base64OfSize(MAX_IMAGE_BYTES);

    expect(decodedSizeInBytes(atLimit)).toBe(MAX_IMAGE_BYTES);
    expect(() =>
      validateAnalyzeFoodImageRequest({
        imageBase64: atLimit,
        mimeType: "image/jpeg",
      }),
    ).not.toThrow();
  });
});

describe("handleAnalyzeFoodImage", () => {
  it("returns the analysis for a valid nutrition result", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    const response = await handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client);

    expect(response).toEqual({
      status: "ok",
      analysis: {
        food_name: "Grilled chicken salad",
        description:
          "A plate of mixed leaves with sliced grilled chicken breast.",
        estimated_portion_grams: 320,
        calories: 465,
        protein_grams: 42,
        carbohydrates_grams: 18,
        fat_grams: 24,
        fiber_grams: 6,
        confidence: 0.78,
        assumptions: ["Dressing assumed to be olive oil based."],
        items: [
          { name: "Grilled chicken breast", estimated_portion_grams: 150 },
          { name: "Mixed leaves", estimated_portion_grams: 120 },
        ],
      },
    });
  });

  it("passes the validated image straight to the model", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    await handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client);

    expect(client.calls).toEqual([
      { data: VALID_BASE64, mimeType: "image/jpeg" },
    ]);
  });

  it("reports a no-food photo without inventing nutrition values", async () => {
    const client = respondingWith({
      ...FOOD_RESPONSE,
      food_detected: false,
      no_food_reason: "The photo shows a laptop keyboard.",
    });

    const response = await handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client);

    expect(response).toEqual({
      status: "no_food_detected",
      reason: "The photo shows a laptop keyboard.",
    });
    expect(response).not.toHaveProperty("analysis");
  });

  it("falls back to a readable reason when the model gives none", async () => {
    const client = respondingWith({
      ...FOOD_RESPONSE,
      food_detected: false,
      no_food_reason: "",
    });

    const response = await handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client);

    expect(response).toEqual({
      status: "no_food_detected",
      reason: "The photo does not appear to contain food.",
    });
  });

  it("rejects malformed model output instead of passing it on", async () => {
    const malformed: unknown[] = [
      null,
      "not json",
      {},
      { ...FOOD_RESPONSE, food_detected: "yes" },
      { ...FOOD_RESPONSE, calories: "465" },
      { ...FOOD_RESPONSE, calories: Number.NaN },
      { ...FOOD_RESPONSE, calories: -10 },
      { ...FOOD_RESPONSE, confidence: 42 },
      { ...FOOD_RESPONSE, food_name: "" },
      { ...FOOD_RESPONSE, assumptions: "none" },
      { ...FOOD_RESPONSE, items: [{ name: "Rice" }] },
      { ...FOOD_RESPONSE, items: [{ estimated_portion_grams: 100 }] },
    ];

    for (const value of malformed) {
      await expectFailure(
        () => handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), respondingWith(value)),
        "internal",
      );
    }
  });

  it("maps a busy model to `unavailable`", async () => {
    const client = failingWith(
      new GeminiError("unavailable", "The model is busy."),
    );

    const error = await expectFailure(
      () => handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client),
      "unavailable",
    );
    expect(error.message).toContain("try again");
  });

  it("maps an exhausted quota to `resource-exhausted`", async () => {
    const client = failingWith(
      new GeminiError("rate_limited", "The model quota is exhausted."),
    );

    await expectFailure(
      () => handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client),
      "resource-exhausted",
    );
  });

  it("maps any other Gemini failure to `internal`", async () => {
    for (const error of [
      new GeminiError("failed", "The model request failed."),
      new Error("socket hang up"),
    ]) {
      await expectFailure(
        () => handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), failingWith(error)),
        "internal",
      );
    }
  });

  it("never leaks the model's raw failure text to the client", async () => {
    const client = failingWith(new Error("key=super-secret-value"));

    const error = await expectFailure(
      () => handleAnalyzeFoodImage(signedInCall(VALID_REQUEST), client),
      "internal",
    );
    expect(error.message).not.toContain("super-secret-value");
  });

  it("rejects a bad request before calling the model", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    await expectFailure(
      () => handleAnalyzeFoodImage(signedInCall({ mimeType: "image/jpeg" }), client),
      "invalid-argument",
    );
    expect(client.calls).toHaveLength(0);
  });
});

describe("authentication is enforced", () => {
  it("rejects a call with no caller", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    const error = await expectFailure(
      () => handleAnalyzeFoodImage({ data: VALID_REQUEST }, client),
      "unauthenticated",
    );
    expect(error.message).toBe("Sign in to analyse a photo.");
  });

  it("rejects a call whose caller is null or has no uid", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    for (const auth of [null, undefined, { uid: "" }]) {
      await expectFailure(
        () =>
          handleAnalyzeFoodImage(
            { data: VALID_REQUEST, auth } as Parameters<
              typeof handleAnalyzeFoodImage
            >[0],
            client,
          ),
        "unauthenticated",
      );
    }
  });

  it("never reaches Gemini when the caller is missing", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    await expectFailure(
      () => handleAnalyzeFoodImage({ data: VALID_REQUEST }, client),
      "unauthenticated",
    );

    expect(client.calls).toHaveLength(0);
  });

  it("checks the caller before validating the request", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    // A request that is both unauthenticated and malformed comes back as
    // unauthenticated: the caller is checked first.
    await expectFailure(
      () => handleAnalyzeFoodImage({ data: { mimeType: "image/gif" } }, client),
      "unauthenticated",
    );
    expect(client.calls).toHaveLength(0);
  });

  it("lets a signed-in caller through to the model", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    const response = await handleAnalyzeFoodImage(
      signedInCall(VALID_REQUEST),
      client,
    );

    expect(response.status).toBe("ok");
    expect(client.calls).toHaveLength(1);
  });

  it("still rejects a bad request from a signed-in caller", async () => {
    const oversized = base64OfSize(MAX_IMAGE_BYTES + 1);

    for (const data of [
      { imageBase64: "", mimeType: "image/jpeg" },
      { imageBase64: VALID_BASE64, mimeType: "image/gif" },
      { imageBase64: "not base64!!", mimeType: "image/png" },
      { imageBase64: oversized, mimeType: "image/jpeg" },
    ]) {
      const client = respondingWith(FOOD_RESPONSE);

      await expectFailure(
        () => handleAnalyzeFoodImage(signedInCall(data), client),
        "invalid-argument",
      );
      expect(client.calls).toHaveLength(0);
    }
  });

  it("does not put the caller's uid in the error message", async () => {
    const client = respondingWith(FOOD_RESPONSE);

    const error = await expectFailure(
      () =>
        handleAnalyzeFoodImage(
          { data: VALID_REQUEST, auth: { uid: "secret-uid-123" } },
          respondingWith(null),
        ),
      "internal",
    );
    expect(error.message).not.toContain("secret-uid-123");
    expect(client.calls).toHaveLength(0);
  });
});

describe("createGeminiClient", () => {
  it("refuses to build a client without an API key", () => {
    expect(() => createGeminiClient("")).toThrowError(
      "GEMINI_API_KEY is not configured.",
    );
  });
});
