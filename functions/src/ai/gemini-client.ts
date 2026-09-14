import { GoogleGenAI, Type } from "@google/genai";

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

/** Safe, bounded metadata suitable for structured server logs. */
export interface GeminiErrorDiagnostics {
  httpStatus?: number;
  upstreamCode?: string | number;
  upstreamMessage?: string;
  model: string;
  retryable: boolean;
  sdkErrorName: string;
  sdkErrorType: string;
}

export class GeminiError extends Error {
  constructor(
    readonly kind: GeminiFailureKind,
    message: string,
    readonly diagnostics: GeminiErrorDiagnostics = {
      model: GEMINI_MODEL,
      retryable: kind !== "failed",
      sdkErrorName: "GeminiError",
      sdkErrorType: "GeminiError",
    },
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

type UnknownRecord = Record<string, unknown>;

const MAX_DIAGNOSTIC_MESSAGE_LENGTH = 500;

function asRecord(value: unknown): UnknownRecord | undefined {
  return typeof value === "object" && value !== null
    ? (value as UnknownRecord)
    : undefined;
}

function safeErrorLabel(value: unknown, fallback: string): string {
  return typeof value === "string" && /^[A-Za-z0-9_.-]{1,80}$/.test(value)
    ? value
    : fallback;
}

/** Removes credentials and payload-like blobs before any upstream text is logged. */
function safeDiagnosticMessage(
  value: string,
  sensitiveValues: readonly string[],
): string {
  let safe = value;

  for (const secret of sensitiveValues) {
    if (secret.length >= 4) safe = safe.split(secret).join("[REDACTED]");
  }

  safe = safe
    .replace(/-----BEGIN [^-]+-----[\s\S]*?-----END [^-]+-----/gi, "[REDACTED_PEM]")
    .replace(/\bBearer\s+[^\s"']+/gi, "Bearer [REDACTED]")
    .replace(
      /([?&](?:key|api_key|token|access_token)=)[^&\s"']+/gi,
      "$1[REDACTED]",
    )
    .replace(/\bAIza[A-Za-z0-9_-]{20,}\b/g, "[REDACTED_API_KEY]")
    .replace(
      /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b/g,
      "[REDACTED_TOKEN]",
    )
    .replace(/[A-Za-z0-9+/_=-]{200,}/g, "[REDACTED_DATA]")
    .replace(/\s+/g, " ")
    .trim();

  return safe.length <= MAX_DIAGNOSTIC_MESSAGE_LENGTH
    ? safe
    : `${safe.slice(0, MAX_DIAGNOSTIC_MESSAGE_LENGTH)}…`;
}

function numericStatus(record: UnknownRecord | undefined): number | undefined {
  for (const field of ["status", "statusCode"]) {
    const value = record?.[field];
    if (typeof value === "number" && Number.isInteger(value)) return value;
  }
  return undefined;
}

function parsedUpstreamError(message: string): UnknownRecord | undefined {
  try {
    return asRecord(asRecord(JSON.parse(message))?.["error"]);
  } catch {
    return undefined;
  }
}

function retryableFailure(
  kind: GeminiFailureKind,
  httpStatus: number | undefined,
  upstreamCode: string | number | undefined,
  sdkErrorName: string,
): boolean {
  if (kind === "unavailable" || kind === "rate_limited") return true;
  if (sdkErrorName === "AbortError") return true;
  if (
    httpStatus !== undefined &&
    [408, 429, 500, 502, 503, 504].includes(httpStatus)
  ) {
    return true;
  }
  return (
    typeof upstreamCode === "string" &&
    ["ABORTED", "DEADLINE_EXCEEDED", "RESOURCE_EXHAUSTED", "UNAVAILABLE"].includes(
      upstreamCode.toUpperCase(),
    )
  );
}

/** Maps an SDK error to a safe user kind plus redacted diagnostic metadata. */
export function toGeminiError(
  error: unknown,
  sensitiveValues: readonly string[] = [],
): GeminiError {
  const message = error instanceof Error ? error.message : String(error);
  const record = asRecord(error);
  const upstream = parsedUpstreamError(message);
  const httpStatus = numericStatus(record) ??
    (typeof upstream?.["code"] === "number" ? upstream["code"] : undefined);
  const rawUpstreamCode = upstream?.["status"] ?? record?.["code"];
  const upstreamCode =
    typeof rawUpstreamCode === "string" || typeof rawUpstreamCode === "number"
      ? rawUpstreamCode
      : undefined;
  const rawUpstreamMessage =
    typeof upstream?.["message"] === "string"
      ? upstream["message"]
      : message;
  const sdkErrorName = safeErrorLabel(record?.["name"], "UnknownError");
  const sdkErrorType = safeErrorLabel(
    error instanceof Error ? error.constructor.name : typeof error,
    "UnknownError",
  );

  let kind: GeminiFailureKind = "failed";

  if (error instanceof Error && error.name === "AbortError") {
    kind = "unavailable";
  } else if (message.includes("503") || message.includes("UNAVAILABLE")) {
    kind = "unavailable";
  } else if (message.includes("429") || message.includes("RESOURCE_EXHAUSTED")) {
    kind = "rate_limited";
  }

  const userSafeMessage =
    error instanceof Error && error.name === "AbortError"
      ? "The analysis timed out."
      : kind === "unavailable"
        ? "The model is busy."
        : kind === "rate_limited"
          ? "The model quota is exhausted."
          : "The model request failed.";

  return new GeminiError(kind, userSafeMessage, {
    httpStatus,
    upstreamCode,
    upstreamMessage: safeDiagnosticMessage(
      rawUpstreamMessage,
      sensitiveValues,
    ),
    model: GEMINI_MODEL,
    retryable: retryableFailure(
      kind,
      httpStatus,
      upstreamCode,
      sdkErrorName,
    ),
    sdkErrorName,
    sdkErrorType,
  });
}

class GoogleGeminiClient implements GeminiClient {
  constructor(
    private readonly ai: GoogleGenAI,
    private readonly sensitiveValues: readonly string[],
  ) {}

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
      throw toGeminiError(error, this.sensitiveValues);
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
  return new GoogleGeminiClient(new GoogleGenAI({ apiKey }), [
    apiKey,
    process.env.GEMINI_API_KEY ?? "",
    process.env.FIREBASE_PRIVATE_KEY ?? "",
    process.env.UPSTASH_REDIS_REST_TOKEN ?? "",
  ]);
}
