import {
  GeminiError,
  createGeminiClient,
} from "../functions/src/ai/gemini-client.js";
import type {
  GeminiClient,
} from "../functions/src/ai/gemini-client.js";
import {
  MalformedAnalysisError,
  parseAnalysisResponse,
} from "../functions/src/ai/parse-analysis.js";
import {
  RequestValidationError,
  parseAnalyzeFoodImageRequest,
} from "../functions/src/ai/validate-request.js";
import { MAX_IMAGE_BYTES } from "../functions/src/types/nutrition.js";
import { BackendConfigurationError } from "./auth.js";
import type { TokenVerifier } from "./auth.js";
import type { UserRateLimiter } from "./rate-limit.js";

// A 3 MiB image becomes exactly 4 MiB when base64 encoded. Reserve 1 KiB for
// the JSON field names and MIME type while staying below Vercel's 4.5 MB cap.
const MAX_HTTP_BODY_BYTES =
  Math.ceil(MAX_IMAGE_BYTES / 3) * 4 + 1024;

export interface AnalyzeFoodDependencies {
  tokenVerifier: TokenVerifier;
  rateLimiter: UserRateLimiter;
  createGeminiClient(): GeminiClient;
}

interface ErrorBody {
  error: { code: string; message: string };
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  headers?: HeadersInit,
): Response {
  const body: ErrorBody = { error: { code, message } };
  return Response.json(body, { status, headers });
}

function bearerToken(request: Request): string | null {
  const value = request.headers.get("authorization");
  if (!value) return null;
  const match = /^Bearer ([^\s]+)$/i.exec(value);
  return match?.[1] ?? null;
}

async function readJsonBody(request: Request): Promise<unknown> {
  const length = request.headers.get("content-length");
  if (length !== null) {
    const bytes = Number(length);
    if (Number.isFinite(bytes) && bytes > MAX_HTTP_BODY_BYTES) {
      throw new RequestValidationError(
        "Request body is too large.",
        "image_too_large",
      );
    }
  }

  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    throw new RequestValidationError("Content-Type must be application/json.");
  }

  const body = await request.text();
  if (new TextEncoder().encode(body).byteLength > MAX_HTTP_BODY_BYTES) {
    throw new RequestValidationError(
      "Request body is too large.",
      "image_too_large",
    );
  }

  try {
    return JSON.parse(body) as unknown;
  } catch {
    throw new RequestValidationError("Request body must be valid JSON.");
  }
}

/** Builds an independently testable Web-standard Vercel handler. */
export function createAnalyzeFoodHandler(
  dependencies: AnalyzeFoodDependencies,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return errorResponse(405, "method_not_allowed", "Use POST for this endpoint.", {
        Allow: "POST",
      });
    }

    const token = bearerToken(request);
    if (!token) {
      return errorResponse(401, "unauthenticated", "Sign in to analyse a photo.");
    }

    let uid: string;
    try {
      ({ uid } = await dependencies.tokenVerifier.verifyIdToken(token));
      if (!uid) throw new Error("Token has no uid.");
    } catch (error) {
      if (error instanceof BackendConfigurationError) {
        console.error("Food analysis authentication is not configured");
        return errorResponse(
          503,
          "unavailable",
          "The analysis service is unavailable. Please try again later.",
        );
      }
      console.warn("Food analysis rejected an invalid Firebase ID token");
      return errorResponse(401, "unauthenticated", "Sign in to analyse a photo.");
    }

    let image;
    try {
      image = parseAnalyzeFoodImageRequest(await readJsonBody(request));
    } catch (error) {
      if (error instanceof RequestValidationError) {
        if (error.code === "image_too_large") {
          return errorResponse(
            413,
            "image_too_large",
            "That photo is too large. Choose a smaller image and try again.",
          );
        }
        return errorResponse(
          400,
          "invalid_argument",
          "That photo could not be used. Try a different one.",
        );
      }
      return errorResponse(400, "invalid_argument", "Request body is invalid.");
    }

    try {
      const limit = await dependencies.rateLimiter.check(uid);
      if (!limit.allowed) {
        const retryAfter = String(limit.retryAfterSeconds ?? 60);
        return errorResponse(
          429,
          "rate_limited",
          "You have reached the scan limit. Please try again later.",
          { "Retry-After": retryAfter },
        );
      }
    } catch {
      console.error("Food analysis rate limiter is unavailable");
      return errorResponse(
        503,
        "unavailable",
        "The analysis service is unavailable. Please try again later.",
      );
    }

    let client: GeminiClient;
    try {
      client = dependencies.createGeminiClient();
    } catch {
      console.error("Food analysis model is not configured");
      return errorResponse(
        503,
        "unavailable",
        "The analysis service is unavailable. Please try again later.",
      );
    }

    try {
      const raw = await client.analyzeFoodImage({
        data: image.imageBase64,
        mimeType: image.mimeType,
      });
      return Response.json(parseAnalysisResponse(raw));
    } catch (error) {
      if (error instanceof MalformedAnalysisError) {
        console.error("Gemini returned malformed food analysis output");
        return errorResponse(
          502,
          "malformed_response",
          "The analysis came back in an unexpected format. Please try again.",
        );
      }
      if (error instanceof GeminiError) {
        console.error("Gemini food analysis request failed", { kind: error.kind });
        if (error.kind === "unavailable") {
          return errorResponse(
            503,
            "unavailable",
            "The analysis service is busy. Please try again in a moment.",
          );
        }
        if (error.kind === "rate_limited") {
          return errorResponse(
            503,
            "model_rate_limited",
            "The analysis quota has run out. Please try again later.",
          );
        }
      } else {
        console.error("Unexpected food analysis failure");
      }
      return errorResponse(
        500,
        "internal",
        "The photo could not be analysed. Please try again.",
      );
    }
  };
}

export function geminiClientFromEnvironment(): GeminiClient {
  return createGeminiClient(process.env.GEMINI_API_KEY ?? "");
}
