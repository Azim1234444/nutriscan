import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

import { BackendConfigurationError } from "./auth.js";

export interface RateLimitDecision {
  allowed: boolean;
  retryAfterSeconds?: number;
}

export interface UserRateLimiter {
  check(uid: string): Promise<RateLimitDecision>;
}

function requiredEnvironmentValue(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new BackendConfigurationError(`${name} is not configured.`);
  }
  return value;
}

/**
 * Creates durable limits backed by Upstash Redis.
 *
 * There is deliberately no in-memory fallback: separate serverless instances
 * do not share memory, so silently falling back would make the limits illusory.
 */
export function createUserRateLimiter(): UserRateLimiter {
  const redis = new Redis({
    url: requiredEnvironmentValue("UPSTASH_REDIS_REST_URL"),
    token: requiredEnvironmentValue("UPSTASH_REDIS_REST_TOKEN"),
  });
  const hourly = new Ratelimit({
    redis,
    prefix: "nutriscan:scan:hour",
    limiter: Ratelimit.fixedWindow(10, "1 h"),
  });
  const daily = new Ratelimit({
    redis,
    prefix: "nutriscan:scan:day",
    limiter: Ratelimit.fixedWindow(30, "1 d"),
  });

  return {
    async check(uid: string): Promise<RateLimitDecision> {
      const hour = await hourly.limit(uid);
      if (!hour.success) {
        return {
          allowed: false,
          retryAfterSeconds: secondsUntil(hour.reset),
        };
      }

      const day = await daily.limit(uid);
      if (!day.success) {
        return {
          allowed: false,
          retryAfterSeconds: secondsUntil(day.reset),
        };
      }
      return { allowed: true };
    },
  };
}

function secondsUntil(resetAtMs: number): number {
  return Math.max(1, Math.ceil((resetAtMs - Date.now()) / 1000));
}
