import { describe, expect, it, vi } from "vitest";

import {
  createAnalyzeFoodHandler,
} from "../backend/analyze-food-handler.js";
import type { AnalyzeFoodDependencies } from "../backend/analyze-food-handler.js";
import type { TokenVerifier } from "../backend/auth.js";
import type { UserRateLimiter } from "../backend/rate-limit.js";
import type {
  FoodImage,
  GeminiClient,
} from "../functions/src/ai/gemini-client.js";
import { GeminiError } from "../functions/src/ai/gemini-client.js";
import { MAX_IMAGE_BYTES } from "../functions/src/types/nutrition.js";

const imageBase64 = Buffer.from("pretend-image").toString("base64");
const requestBody = { imageBase64, mimeType: "image/jpeg" };
const modelResponse = {
  food_detected: true,
  no_food_reason: "",
  food_name: "Rice bowl",
  description: "Rice with vegetables.",
  estimated_portion_grams: 350,
  calories: 510,
  protein_grams: 18,
  carbohydrates_grams: 82,
  fat_grams: 12,
  fiber_grams: 7,
  confidence: 0.8,
  assumptions: ["The sauce is lightly sweetened."],
  items: [{ name: "Rice", estimated_portion_grams: 220 }],
};

class FakeGeminiClient implements GeminiClient {
  calls: FoodImage[] = [];

  constructor(
    private readonly result: unknown = modelResponse,
    private readonly error?: Error,
  ) {}

  async analyzeFoodImage(image: FoodImage): Promise<unknown> {
    this.calls.push(image);
    if (this.error) throw this.error;
    return this.result;
  }
}

class SequencedGeminiClient implements GeminiClient {
  calls: FoodImage[] = [];

  constructor(private readonly outcomes: readonly unknown[]) {}

  async analyzeFoodImage(image: FoodImage): Promise<unknown> {
    this.calls.push(image);
    const outcome = this.outcomes[this.calls.length - 1];
    if (outcome instanceof Error) throw outcome;
    return outcome;
  }
}

function dependencies(options?: {
  verifier?: TokenVerifier;
  limiter?: UserRateLimiter;
  gemini?: GeminiClient;
  sleep?: (milliseconds: number) => Promise<void>;
  random?: () => number;
}): AnalyzeFoodDependencies {
  const gemini = options?.gemini ?? new FakeGeminiClient();
  return {
    tokenVerifier:
      options?.verifier ??
      ({ verifyIdToken: async () => ({ uid: "user-123" }) } satisfies TokenVerifier),
    rateLimiter:
      options?.limiter ??
      ({ check: async () => ({ allowed: true }) } satisfies UserRateLimiter),
    createGeminiClient: () => gemini,
    sleep: options?.sleep,
    random: options?.random,
  };
}

function retryableGeminiError(): GeminiError {
  return new GeminiError("unavailable", "The model is busy.", {
    httpStatus: 503,
    upstreamCode: "UNAVAILABLE",
    upstreamMessage: "The service is temporarily unavailable.",
    model: "gemini-3.5-flash",
    retryable: true,
    sdkErrorName: "ApiError",
    sdkErrorType: "ApiError",
  });
}

function post(body: unknown = requestBody, token = "valid-token"): Request {
  return new Request("https://example.test/api/analyze-food", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function base64OfSize(bytes: number): string {
  const groups = Math.ceil(bytes / 3);
  const padding = groups * 3 - bytes;
  return "A".repeat(groups * 4 - padding) + "=".repeat(padding);
}

describe("POST /api/analyze-food", () => {
  it("returns the existing nutrition response contract", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    const gemini = new FakeGeminiClient();
    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(post());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      analysis: {
        food_name: "Rice bowl",
        description: "Rice with vegetables.",
        estimated_portion_grams: 350,
        calories: 510,
        protein_grams: 18,
        carbohydrates_grams: 82,
        fat_grams: 12,
        fiber_grams: 7,
        confidence: 0.8,
        assumptions: ["The sauce is lightly sweetened."],
        items: [{ name: "Rice", estimated_portion_grams: 220 }],
      },
    });
    expect(gemini.calls).toEqual([{ data: imageBase64, mimeType: "image/jpeg" }]);
  });

  it("succeeds after one retryable failure", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    const warning = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const delays: number[] = [];
    const limiter = { check: vi.fn(async () => ({ allowed: true })) };
    const gemini = new SequencedGeminiClient([
      retryableGeminiError(),
      modelResponse,
    ]);

    const response = await createAnalyzeFoodHandler(
      dependencies({
        gemini,
        limiter,
        random: () => 0,
        sleep: async (milliseconds) => {
          delays.push(milliseconds);
        },
      }),
    )(post());

    expect(response.status).toBe(200);
    expect(gemini.calls).toHaveLength(2);
    expect(limiter.check).toHaveBeenCalledTimes(1);
    expect(delays).toEqual([750]);
    expect(warning).toHaveBeenCalledWith(
      "Gemini food analysis retry scheduled",
      expect.objectContaining({
        attempt: 1,
        nextAttempt: 2,
        retryScheduled: true,
        retryDelayMs: 750,
      }),
    );
  });

  it("succeeds after two retryable failures", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const delays: number[] = [];
    const gemini = new SequencedGeminiClient([
      retryableGeminiError(),
      retryableGeminiError(),
      modelResponse,
    ]);

    const response = await createAnalyzeFoodHandler(
      dependencies({
        gemini,
        random: () => 0,
        sleep: async (milliseconds) => {
          delays.push(milliseconds);
        },
      }),
    )(post());

    expect(response.status).toBe(200);
    expect(gemini.calls).toHaveLength(3);
    expect(delays).toEqual([750, 1500]);
  });

  it("returns the existing 503 after three retryable failures", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const limiter = { check: vi.fn(async () => ({ allowed: true })) };
    const gemini = new SequencedGeminiClient([
      retryableGeminiError(),
      retryableGeminiError(),
      retryableGeminiError(),
    ]);

    const response = await createAnalyzeFoodHandler(
      dependencies({
        gemini,
        limiter,
        random: () => 0,
        sleep: async () => undefined,
      }),
    )(post());

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      error: {
        code: "unavailable",
        message: "The analysis service is busy. Please try again in a moment.",
      },
    });
    expect(gemini.calls).toHaveLength(3);
    expect(limiter.check).toHaveBeenCalledTimes(1);
    expect(log).toHaveBeenCalledWith(
      "Gemini food analysis request failed",
      expect.objectContaining({
        attempt: 3,
        retryScheduled: false,
        retryExhausted: true,
      }),
    );
  });

  it("does not retry a non-retryable Gemini failure", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const sleep = vi.fn(async () => undefined);
    const gemini = new SequencedGeminiClient([
      new GeminiError("failed", "The model request failed.", {
        httpStatus: 400,
        upstreamCode: "INVALID_ARGUMENT",
        upstreamMessage: "Invalid request.",
        model: "gemini-3.5-flash",
        retryable: false,
        sdkErrorName: "ApiError",
        sdkErrorType: "ApiError",
      }),
      modelResponse,
    ]);

    const response = await createAnalyzeFoodHandler(
      dependencies({ gemini, sleep }),
    )(post());

    expect(response.status).toBe(500);
    expect(gemini.calls).toHaveLength(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("rejects a missing auth token before Gemini", async () => {
    const gemini = new FakeGeminiClient();
    const request = new Request("https://example.test/api/analyze-food", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(requestBody),
    });

    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(request);

    expect(response.status).toBe(401);
    expect(gemini.calls).toHaveLength(0);
  });

  it("rejects an invalid token before Gemini", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const gemini = new FakeGeminiClient();
    const verifier: TokenVerifier = {
      verifyIdToken: async () => {
        throw new Error("bad signature");
      },
    };

    const response = await createAnalyzeFoodHandler(
      dependencies({ verifier, gemini }),
    )(post());

    expect(response.status).toBe(401);
    expect(gemini.calls).toHaveLength(0);
  });

  it("returns 429 without calling Gemini when the user is rate limited", async () => {
    const gemini = new FakeGeminiClient();
    const limiter: UserRateLimiter = {
      check: async () => ({ allowed: false, retryAfterSeconds: 120 }),
    };

    const response = await createAnalyzeFoodHandler(
      dependencies({ limiter, gemini }),
    )(post());

    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("120");
    expect(gemini.calls).toHaveLength(0);
  });

  it("maps an unexpected backend failure without leaking it", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const gemini = new FakeGeminiClient(undefined, new Error("secret internals"));

    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(post());
    const body = await response.text();

    expect(response.status).toBe(500);
    expect(body).not.toContain("secret internals");
  });

  it("logs safe Gemini diagnostics without changing the client response", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const gemini = new FakeGeminiClient(
      undefined,
      new GeminiError("unavailable", "The model is busy.", {
        httpStatus: 503,
        upstreamCode: "UNAVAILABLE",
        upstreamMessage: "The service is temporarily unavailable.",
        model: "gemini-3.5-flash",
        retryable: true,
        sdkErrorName: "ApiError",
        sdkErrorType: "ApiError",
      }),
    );

    const response = await createAnalyzeFoodHandler(
      dependencies({ gemini, sleep: async () => undefined }),
    )(post());

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      error: {
        code: "unavailable",
        message: "The analysis service is busy. Please try again in a moment.",
      },
    });
    expect(log).toHaveBeenCalledWith("Gemini food analysis request failed", {
      attempt: 3,
      maxAttempts: 3,
      retryScheduled: false,
      retryExhausted: true,
      kind: "unavailable",
      httpStatus: 503,
      upstreamCode: "UNAVAILABLE",
      upstreamMessage: "The service is temporarily unavailable.",
      model: "gemini-3.5-flash",
      retryable: true,
      sdkErrorName: "ApiError",
      sdkErrorType: "ApiError",
    });
  });

  it("rejects malformed model output", async () => {
    vi.spyOn(console, "info").mockImplementation(() => undefined);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const gemini = new FakeGeminiClient({ ...modelResponse, calories: "510" });

    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(post());

    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({
      error: { code: "malformed_response" },
    });
    expect(gemini.calls).toHaveLength(1);
  });

  it("rejects unsupported methods and malformed requests", async () => {
    const handler = createAnalyzeFoodHandler(dependencies());
    const getResponse = await handler(
      new Request("https://example.test/api/analyze-food"),
    );
    const badResponse = await handler(post({ imageBase64, mimeType: "image/gif" }));

    expect(getResponse.status).toBe(405);
    expect(getResponse.headers.get("allow")).toBe("POST");
    expect(badResponse.status).toBe(400);
  });

  it("returns a clear 413 for an image over 3 MiB before Gemini", async () => {
    const gemini = new FakeGeminiClient();
    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(
      post({
        imageBase64: base64OfSize(MAX_IMAGE_BYTES + 1),
        mimeType: "image/jpeg",
      }),
    );

    expect(MAX_IMAGE_BYTES).toBe(3 * 1024 * 1024);
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({
      error: {
        code: "image_too_large",
        message: "That photo is too large. Choose a smaller image and try again.",
      },
    });
    expect(gemini.calls).toHaveLength(0);
  });

  it("accepts exactly 3 MiB with JSON headroom below 4.5 MiB", async () => {
    const gemini = new FakeGeminiClient();
    const body = {
      imageBase64: base64OfSize(MAX_IMAGE_BYTES),
      mimeType: "image/jpeg",
    };
    const encodedBody = JSON.stringify(body);

    expect(new TextEncoder().encode(encodedBody).byteLength).toBeLessThan(
      4.5 * 1024 * 1024,
    );

    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(
      post(body),
    );

    expect(response.status).toBe(200);
    expect(gemini.calls).toHaveLength(1);
  });
});
