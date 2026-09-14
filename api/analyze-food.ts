import {
  createAnalyzeFoodHandler,
  geminiClientFromEnvironment,
} from "../backend/analyze-food-handler.js";
import { createFirebaseTokenVerifier } from "../backend/auth.js";
import { createUserRateLimiter } from "../backend/rate-limit.js";
import type { UserRateLimiter } from "../backend/rate-limit.js";

let rateLimiter: UserRateLimiter | undefined;

const handler = createAnalyzeFoodHandler({
  tokenVerifier: createFirebaseTokenVerifier(),
  rateLimiter: {
    check(uid: string) {
      rateLimiter ??= createUserRateLimiter();
      return rateLimiter.check(uid);
    },
  },
  createGeminiClient: geminiClientFromEnvironment,
});

export default {
  fetch(request: Request): Promise<Response> {
    return handler(request);
  },
};
