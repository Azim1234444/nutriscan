/**
 * Request and response contracts shared by the food analysis backend.
 *
 * The field names in {@link NutritionAnalysis} are the ones Gemini will be
 * asked to produce in phase 2B-2, and the ones the Flutter client will parse,
 * so they use snake_case on purpose - keep them stable.
 */

/** Image formats the backend accepts. Anything else is rejected. */
export const SUPPORTED_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

export type SupportedMimeType = (typeof SUPPORTED_MIME_TYPES)[number];

/**
 * Largest decoded image the callable accepts, in bytes.
 *
 * The app already downscales photos to 1600px at 85% quality (a few hundred
 * KB), so 5 MB is generous while keeping the request well under the callable
 * payload limit.
 */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

/** Firestore-validated limits for the model's supporting metadata. */
export const MAX_ASSUMPTIONS = 3;
export const MAX_NUTRITION_ITEMS = 5;
export const MAX_AI_METADATA_ENTRIES = 6;
export const MAX_ASSUMPTION_LENGTH = 500;
export const MAX_NUTRITION_ITEM_NAME_LENGTH = 200;

/** What the Flutter client sends to `analyzeFoodImage`. */
export interface AnalyzeFoodImageRequest {
  /** Raw base64 of the image bytes - no `data:` URL prefix. */
  imageBase64: string;
  mimeType: SupportedMimeType;
}

/** One recognised component of a meal, e.g. "grilled chicken breast". */
export interface NutritionItem {
  name: string;
  estimated_portion_grams: number;
}

/**
 * The structured result the model returns for a photo containing food.
 *
 * Field names are snake_case because they are part of the model's response
 * schema and of the JSON the Flutter client parses - keep them stable.
 */
export interface NutritionAnalysis {
  food_name: string;
  description: string;
  estimated_portion_grams: number;
  calories: number;
  protein_grams: number;
  carbohydrates_grams: number;
  fat_grams: number;
  fiber_grams: number;
  /** Model confidence between 0 and 1. */
  confidence: number;
  /** Plain-language notes about what had to be guessed, e.g. portion size. */
  assumptions: string[];
  items: NutritionItem[];
}

/** A photo the model recognised as food. */
export interface AnalysisSuccessResponse {
  status: "ok";
  analysis: NutritionAnalysis;
}

/**
 * A photo with no food in it.
 *
 * A separate response rather than an error: the user did nothing wrong, and
 * the backend must never invent numbers to fill this case.
 */
export interface NoFoodDetectedResponse {
  status: "no_food_detected";
  reason: string;
}

/** Tagged union so the client can branch on `status` alone. */
export type AnalyzeFoodImageResponse =
  | AnalysisSuccessResponse
  | NoFoodDetectedResponse;
