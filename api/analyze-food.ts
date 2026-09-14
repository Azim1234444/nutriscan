import { createAnalyzeFoodHandler, geminiClientFromEnvironment } from "../backend/analyze-food-handler";
import { createFirebaseTokenVerifier } from "../backend/auth";
import { createUserRateLimiter, UserRateLimiter } from "../backend/rate-limit";

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
