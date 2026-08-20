import { GoogleGenAI, Type } from "@google/genai";
import { defineSecret } from "firebase-functions/params";

/**
 * Handle to the Gemini API key stored in Google Secret Manager.
 *
 * `defineSecret` only declares the binding - the value is injected into the
 * function's environment at runtime and never appears in this repository, in
 * the deployed client bundle, or in logs. Functions that need it must list it
 * in their `secrets` option. Locally the Functions emulator reads it from the
 * git-ignored `functions/.secret.local`.
 */
export const geminiApiKey = defineSecret("GEMINI_API_KEY");

/**
 * Model used for food analysis.
 *
 * Stable, multimodal and fast enough for a callable request. Swapping models
 * is a one-line change here.
 */
export const GEMINI_MODEL = "gemini-3.5-flash";

/** How long to wait for the model before giving up, in milliseconds. */
const GEMINI_TIMEOUT_MS = 45_000;

/** An image handed to the model, already validated by the callable. */
export interface FoodImage {
  /** Base64 image bytes without a `data:` URL prefix. */
  data: string;
  mimeType: string;
}

/** Why a Gemini call failed, so the callable can pick an error code. */
export type GeminiFailureKind = "unavailable" | "rate_limited" | "failed";

export class GeminiError extends Error {
  constructor(
    readonly kind: GeminiFailureKind,
    message: string,
  ) {
    super(message);
    this.name = "GeminiError";
  }
}

/**
 * Server-side boundary in front of Gemini.
 *
 * Returns the model's parsed JSON without vouching for it - the caller
 * validates the shape, so a mock client can feed malformed output to tests.
 */
export interface GeminiClient {
  analyzeFoodImage(image: FoodImage): Promise<unknown>;
}

const SYSTEM_INSTRUCTION = `
You are a nutrition estimation assistant for a food scanning app.
You look at one photo and estimate the nutrition of the food in it.

Rules:
- If the photo does not clearly show food or drink, set food_detected to false,
  explain why in no_food_reason, and set every numeric field to 0. Never guess
  nutrition values for a photo without food in it.
- If food is present, set food_detected to true and estimate the nutrition of
  the whole visible portion, not per 100 g.
- Base estimates on the visible portion size, plate size and preparation style.
- List every distinct component you can identify in items.
- Put anything you had to assume (portion weight, hidden ingredients, cooking
  oil, sauces) into assumptions, as short plain sentences.
- confidence is your own certainty from 0 to 1. Use a low value when the photo
  is blurry, partially hidden, or the portion is hard to judge.
- Estimate honestly. Do not round numbers to look tidy.
`.trim();

const USER_PROMPT = `
Analyse this photo and return the nutrition estimate for the food shown.
`.trim();

/** Structured-output schema. Mirrors NutritionAnalysis plus the food check. */
const RESPONSE_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    food_detected: {
      type: Type.BOOLEAN,
      description: "True only if the photo clearly shows food or drink.",
    },
    no_food_reason: {
      type: Type.STRING,
      description: "Why no food was detected. Empty when food_detected is true.",
    },
    food_name: {
      type: Type.STRING,
      description: "Short name of the meal, e.g. 'Grilled chicken salad'.",
    },
    description: {
      type: Type.STRING,
      description: "One or two sentences describing what is on the plate.",
    },
    estimated_portion_grams: { type: Type.NUMBER },
    calories: { type: Type.NUMBER },
    protein_grams: { type: Type.NUMBER },
    carbohydrates_grams: { type: Type.NUMBER },
    fat_grams: { type: Type.NUMBER },
    fiber_grams: { type: Type.NUMBER },
    confidence: {
      type: Type.NUMBER,
      description: "Certainty from 0 to 1.",
    },
    assumptions: {
      type: Type.ARRAY,
      items: { type: Type.STRING },
    },
    items: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          name: { type: Type.STRING },
          estimated_portion_grams: { type: Type.NUMBER },
        },
        required: ["name", "estimated_portion_grams"],
      },
    },
  },
  required: [
    "food_detected",
    "no_food_reason",
    "food_name",
    "description",
    "estimated_portion_grams",
    "calories",
    "protein_grams",
    "carbohydrates_grams",
    "fat_grams",
    "fiber_grams",
    "confidence",
    "assumptions",
    "items",
  ],
};

/** Maps an SDK error to a failure kind without leaking request details. */
function toGeminiError(error: unknown): GeminiError {
  const message = error instanceof Error ? error.message : String(error);

  if (error instanceof Error && error.name === "AbortError") {
    return new GeminiError("unavailable", "The analysis timed out.");
  }
  if (message.includes("503") || message.includes("UNAVAILABLE")) {
    return new GeminiError("unavailable", "The model is busy.");
  }
  if (message.includes("429") || message.includes("RESOURCE_EXHAUSTED")) {
    return new GeminiError("rate_limited", "The model quota is exhausted.");
  }
  return new GeminiError("failed", "The model request failed.");
}

class GoogleGeminiClient implements GeminiClient {
  constructor(private readonly ai: GoogleGenAI) {}

  async analyzeFoodImage(image: FoodImage): Promise<unknown> {
    let text: string | undefined;

    try {
      const response = await this.ai.models.generateContent({
        model: GEMINI_MODEL,
        contents: [
          {
            role: "user",
            parts: [
              { inlineData: { mimeType: image.mimeType, data: image.data } },
              { text: USER_PROMPT },
            ],
          },
        ],
        config: {
          systemInstruction: SYSTEM_INSTRUCTION,
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA,
          abortSignal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
        },
      });
      text = response.text;
    } catch (error) {
      throw toGeminiError(error);
    }

    if (text === undefined || text.trim().length === 0) {
      throw new GeminiError("failed", "The model returned an empty response.");
    }

    try {
      return JSON.parse(text);
    } catch {
      // The body is not logged: it can echo the photo's contents.
      throw new GeminiError("failed", "The model returned invalid JSON.");
    }
  }
}

/**
 * Builds the client for a request.
 *
 * The key is passed in rather than read from a global so it stays confined to
 * the request that needs it, and it is never logged or returned.
 */
export function createGeminiClient(apiKey: string): GeminiClient {
  if (apiKey.trim().length === 0) {
    throw new Error("GEMINI_API_KEY is not configured.");
  }
  return new GoogleGeminiClient(new GoogleGenAI({ apiKey }));
}
