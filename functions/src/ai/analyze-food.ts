import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import {
  AnalyzeFoodImageRequest,
  AnalyzeFoodImageResponse,
  MAX_IMAGE_BYTES,
  SUPPORTED_MIME_TYPES,
  SupportedMimeType,
} from "../types/nutrition";
import { GeminiClient, GeminiError } from "./gemini-client";
import { MalformedAnalysisError, parseAnalysisResponse } from "./parse-analysis";

/** Standard base64 alphabet with optional padding - no data URLs, no whitespace. */
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * Size of the decoded image, worked out from the base64 length so an
 * oversized payload can be rejected without allocating a buffer for it.
 */
export function decodedSizeInBytes(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.floor((base64.length * 3) / 4) - padding;
}

function isSupportedMimeType(value: string): value is SupportedMimeType {
  return (SUPPORTED_MIME_TYPES as readonly string[]).includes(value);
}

function reject(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function hasBytesAt(
  bytes: Buffer,
  offset: number,
  expected: readonly number[],
): boolean {
  return expected.every((value, index) => bytes[offset + index] === value);
}

function isJpeg(bytes: Buffer): boolean {
  if (
    bytes.length < 4 ||
    !hasBytesAt(bytes, 0, [0xff, 0xd8, 0xff])
  ) {
    return false;
  }

  // A missing end-of-image marker is a strong indication that the upload was
  // truncated. It may be followed by metadata, so do not require it to be the
  // final two bytes.
  for (let index = bytes.length - 2; index >= 3; index -= 1) {
    if (bytes[index] === 0xff && bytes[index + 1] === 0xd9) return true;
  }
  return false;
}

function isPng(bytes: Buffer): boolean {
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

  // A PNG always starts with its signature and a 13-byte IHDR chunk. Requiring
  // the complete first chunk avoids accepting a signature-only truncation.
  return (
    bytes.length >= 33 &&
    hasBytesAt(bytes, 0, pngSignature) &&
    bytes.readUInt32BE(8) === 13 &&
    bytes.toString("ascii", 12, 16) === "IHDR" &&
    bytes.readUInt32BE(16) > 0 &&
    bytes.readUInt32BE(20) > 0
  );
}

function isWebp(bytes: Buffer): boolean {
  if (
    bytes.length < 20 ||
    bytes.toString("ascii", 0, 4) !== "RIFF" ||
    bytes.toString("ascii", 8, 12) !== "WEBP" ||
    bytes.readUInt32LE(4) + 8 !== bytes.length
  ) {
    return false;
  }

  const chunkType = bytes.toString("ascii", 12, 16);
  const chunkSize = bytes.readUInt32LE(16);
  const paddedChunkSize = chunkSize + (chunkSize % 2);
  if (20 + paddedChunkSize > bytes.length) return false;

  switch (chunkType) {
    case "VP8 ":
      return (
        chunkSize >= 10 &&
        hasBytesAt(bytes, 23, [0x9d, 0x01, 0x2a])
      );
    case "VP8L":
      return chunkSize >= 5 && bytes[20] === 0x2f;
    case "VP8X":
      return chunkSize === 10;
    default:
      return false;
  }
}

function imageBytesMatchMimeType(
  bytes: Buffer,
  mimeType: SupportedMimeType,
): boolean {
  switch (mimeType) {
    case "image/jpeg":
      return isJpeg(bytes);
    case "image/png":
      return isPng(bytes);
    case "image/webp":
      return isWebp(bytes);
  }
}

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
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    reject("Request data must be an object.");
  }

  const { imageBase64, mimeType } = data as Record<string, unknown>;

  if (imageBase64 === undefined || imageBase64 === null) {
    reject("imageBase64 is required.");
  }
  if (typeof imageBase64 !== "string") {
    reject("imageBase64 must be a string.");
  }
  if (imageBase64.length === 0 || imageBase64.trim().length === 0) {
    reject("imageBase64 must not be empty.");
  }

  if (typeof mimeType !== "string" || mimeType.length === 0) {
    reject("mimeType is required.");
  }
  if (!isSupportedMimeType(mimeType)) {
    reject(`mimeType must be one of ${SUPPORTED_MIME_TYPES.join(", ")}.`);
  }

  // Size is checked before the pattern so a huge payload is dropped early.
  const sizeInBytes = decodedSizeInBytes(imageBase64);
  if (sizeInBytes > MAX_IMAGE_BYTES) {
    reject(
      `Image is too large: ${sizeInBytes} bytes, maximum is ${MAX_IMAGE_BYTES}.`,
    );
  }

  if (imageBase64.length % 4 !== 0 || !BASE64_PATTERN.test(imageBase64)) {
    reject(
      "imageBase64 must be base64 encoded image bytes without a data URL prefix.",
    );
  }

  const imageBytes = Buffer.from(imageBase64, "base64");
  if (imageBytes.length === 0 || !imageBytesMatchMimeType(imageBytes, mimeType)) {
    reject("Image bytes do not match the declared mimeType or are invalid.");
  }

  return { imageBase64, mimeType };
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
