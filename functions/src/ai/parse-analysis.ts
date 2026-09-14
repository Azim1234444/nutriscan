import type {
  AnalyzeFoodImageResponse,
  NutritionAnalysis,
  NutritionItem,
} from "../types/nutrition.js";

/**
 * Raised when the model's JSON does not match the agreed schema.
 *
 * Structured output makes this unlikely, but "unlikely" is not "never", and a
 * half-parsed analysis would show the user invented numbers.
 */
export class MalformedAnalysisError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MalformedAnalysisError";
  }
}

function fail(field: string, expected: string): never {
  throw new MalformedAnalysisError(`Field "${field}" ${expected}.`);
}

function readString(source: Record<string, unknown>, field: string): string {
  const value = source[field];
  if (typeof value !== "string") fail(field, "must be a string");
  return value.trim();
}

/** Reads a number that must be finite and not negative. */
function readAmount(source: Record<string, unknown>, field: string): number {
  const value = source[field];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(field, "must be a finite number");
  }
  if (value < 0) fail(field, "must not be negative");
  return value;
}

function readStringArray(
  source: Record<string, unknown>,
  field: string,
): string[] {
  const value = source[field];
  if (!Array.isArray(value)) fail(field, "must be an array");
  return value.map((entry, index) => {
    if (typeof entry !== "string") {
      fail(`${field}[${index}]`, "must be a string");
    }
    return entry.trim();
  });
}

function readItems(source: Record<string, unknown>): NutritionItem[] {
  const value = source["items"];
  if (!Array.isArray(value)) fail("items", "must be an array");

  return value.map((entry, index) => {
    if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
      fail(`items[${index}]`, "must be an object");
    }
    const item = entry as Record<string, unknown>;
    const name = readString(item, "name");
    if (name.length === 0) fail(`items[${index}].name`, "must not be empty");

    return {
      name,
      estimated_portion_grams: readAmount(item, "estimated_portion_grams"),
    };
  });
}

/**
 * Turns the model's raw JSON into a response the client can trust.
 *
 * Either returns a fully populated analysis or throws - it never returns a
 * partially filled one.
 *
 * @throws MalformedAnalysisError when a field is missing or the wrong type.
 */
export function parseAnalysisResponse(raw: unknown): AnalyzeFoodImageResponse {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new MalformedAnalysisError("Model response must be an object.");
  }

  const source = raw as Record<string, unknown>;

  const foodDetected = source["food_detected"];
  if (typeof foodDetected !== "boolean") {
    fail("food_detected", "must be a boolean");
  }

  if (!foodDetected) {
    const reason = readString(source, "no_food_reason");
    return {
      status: "no_food_detected",
      reason:
        reason.length > 0
          ? reason
          : "The photo does not appear to contain food.",
    };
  }

  const confidence = readAmount(source, "confidence");
  if (confidence > 1) fail("confidence", "must be between 0 and 1");

  const foodName = readString(source, "food_name");
  if (foodName.length === 0) fail("food_name", "must not be empty");

  const analysis: NutritionAnalysis = {
    food_name: foodName,
    description: readString(source, "description"),
    estimated_portion_grams: readAmount(source, "estimated_portion_grams"),
    calories: readAmount(source, "calories"),
    protein_grams: readAmount(source, "protein_grams"),
    carbohydrates_grams: readAmount(source, "carbohydrates_grams"),
    fat_grams: readAmount(source, "fat_grams"),
    fiber_grams: readAmount(source, "fiber_grams"),
    confidence,
    assumptions: readStringArray(source, "assumptions"),
    items: readItems(source),
  };

  return { status: "ok", analysis };
}
