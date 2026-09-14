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

function dependencies(options?: {
  verifier?: TokenVerifier;
  limiter?: UserRateLimiter;
  gemini?: FakeGeminiClient;
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
  };
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

  it("rejects malformed model output", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const gemini = new FakeGeminiClient({ ...modelResponse, calories: "510" });

    const response = await createAnalyzeFoodHandler(dependencies({ gemini }))(post());

    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({
      error: { code: "malformed_response" },
    });
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
