import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import {
  AnalyzeFoodImageRequest,
  AnalyzeFoodImageResponse,
} from "../types/nutrition";
import { GeminiClient, GeminiError } from "./gemini-client";
import { MalformedAnalysisError, parseAnalysisResponse } from "./parse-analysis";
import {
  decodedSizeInBytes,
  parseAnalyzeFoodImageRequest,
  RequestValidationError,
} from "./validate-request";

export { decodedSizeInBytes } from "./validate-request";

/**
 * Checks untrusted callable input and returns it in a typed shape.
 *
 * Every failure is an `invalid-argument` HttpsError so the client always gets
 * a predictable error code, and the message never echoes the payload back.
 *
 * @throws HttpsError when the request cannot be used.
 */
export function validateAnalyzeFoodImageRequest(
  data: unknown,
): AnalyzeFoodImageRequest {
  try {
    return parseAnalyzeFoodImageRequest(data);
  } catch (error) {
    if (error instanceof RequestValidationError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
}

/** Turns a Gemini failure into the callable error code that fits it. */
function toHttpsError(error: GeminiError): HttpsError {
  switch (error.kind) {
    case "unavailable":
      return new HttpsError(
        "unavailable",
        "The analysis service is busy. Please try again in a moment.",
      );
    case "rate_limited":
      return new HttpsError(
        "resource-exhausted",
        "The analysis quota has run out. Please try again later.",
      );
    case "failed":
      return new HttpsError(
        "internal",
        "The photo could not be analysed. Please try again.",
      );
  }
}

/** The caller, as the callable layer reports them. */
export interface CallerIdentity {
  uid: string;
}

/** One call into the analysis endpoint. */
export interface AnalyzeFoodImageCall {
  data: unknown;

  /** The signed-in caller, or null when the request carries no user. */
  auth?: CallerIdentity | null;
}

/**
 * Checks the caller, validates the request, asks Gemini for an estimate and
 * returns a result the client can trust.
 *
 * The auth check runs first, so an unauthenticated request costs nothing: it
 * is rejected before validation and without ever reaching Gemini.
 *
 * [client] is injected so tests can drive every branch without network access.
 */
export async function handleAnalyzeFoodImage(
  call: AnalyzeFoodImageCall,
  client: GeminiClient,
): Promise<AnalyzeFoodImageResponse> {
  if (!call.auth?.uid) {
    // Nothing identifying is logged - there is no caller to name.
    logger.warn("analyzeFoodImage rejected an unauthenticated request");
    throw new HttpsError("unauthenticated", "Sign in to analyse a photo.");
  }

  const request = validateAnalyzeFoodImageRequest(call.data);
  const imageBytes = decodedSizeInBytes(request.imageBase64);

  // Log shape only. The image bytes and the API key are never logged.
  logger.info("analyzeFoodImage accepted a request", {
    mimeType: request.mimeType,
    imageBytes,
  });

  let raw: unknown;
  try {
    raw = await client.analyzeFoodImage({
      data: request.imageBase64,
      mimeType: request.mimeType,
    });
  } catch (error) {
    if (error instanceof GeminiError) {
      logger.error("Gemini request failed", { kind: error.kind });
      throw toHttpsError(error);
    }
    logger.error("Unexpected analysis failure");
    throw new HttpsError(
      "internal",
      "The photo could not be analysed. Please try again.",
    );
  }

  try {
    const response = parseAnalysisResponse(raw);

    logger.info("analyzeFoodImage produced a result", {
      status: response.status,
      // Names and numbers stay out of the logs; only the shape is recorded.
      itemCount: response.status === "ok" ? response.analysis.items.length : 0,
    });

    return response;
  } catch (error) {
    if (error instanceof MalformedAnalysisError) {
      logger.error("Model returned a malformed analysis", {
        reason: error.message,
      });
      throw new HttpsError(
        "internal",
        "The analysis came back in an unexpected format. Please try again.",
      );
    }
    throw error;
  }
}
