import {
  MAX_IMAGE_BYTES,
  SUPPORTED_MIME_TYPES,
} from "../types/nutrition.js";
import type {
  AnalyzeFoodImageRequest,
  SupportedMimeType,
} from "../types/nutrition.js";

/** Standard base64 alphabet with optional padding - no data URLs or whitespace. */
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

/** A client request that cannot safely be sent to Gemini. */
export class RequestValidationError extends Error {
  constructor(
    message: string,
    readonly code: "invalid_argument" | "image_too_large" = "invalid_argument",
  ) {
    super(message);
    this.name = "RequestValidationError";
  }
}

/** Calculates decoded size without allocating a buffer for untrusted input. */
export function decodedSizeInBytes(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.floor((base64.length * 3) / 4) - padding;
}

function isSupportedMimeType(value: string): value is SupportedMimeType {
  return (SUPPORTED_MIME_TYPES as readonly string[]).includes(value);
}

function reject(message: string): never {
  throw new RequestValidationError(message);
}

/** Validates the transport-independent food-image request contract. */
export function parseAnalyzeFoodImageRequest(
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

  const sizeInBytes = decodedSizeInBytes(imageBase64);
  if (sizeInBytes > MAX_IMAGE_BYTES) {
    throw new RequestValidationError(
      `Image is too large: ${sizeInBytes} bytes, maximum is ${MAX_IMAGE_BYTES}.`,
      "image_too_large",
    );
  }

  if (imageBase64.length % 4 !== 0 || !BASE64_PATTERN.test(imageBase64)) {
    reject(
      "imageBase64 must be base64 encoded image bytes without a data URL prefix.",
    );
  }

  return { imageBase64, mimeType };
}
