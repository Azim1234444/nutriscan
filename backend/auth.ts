import { cert, getApp, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

export interface VerifiedUser {
  uid: string;
}

export interface TokenVerifier {
  verifyIdToken(token: string): Promise<VerifiedUser>;
}

export class BackendConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BackendConfigurationError";
  }
}

function requiredEnvironmentValue(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new BackendConfigurationError(`${name} is not configured.`);
  }
  return value;
}

/** Lazily initializes Firebase Admin using Vercel server-side variables. */
export function createFirebaseTokenVerifier(): TokenVerifier {
  return {
    async verifyIdToken(token: string): Promise<VerifiedUser> {
      const projectId = requiredEnvironmentValue("FIREBASE_PROJECT_ID");
      const usingAuthEmulator = Boolean(
        process.env.FIREBASE_AUTH_EMULATOR_HOST?.trim(),
      );

      const app =
        getApps().length > 0
          ? getApp()
          : usingAuthEmulator
            ? initializeApp({ projectId })
            : initializeApp({
                credential: cert({
                  projectId,
                  clientEmail: requiredEnvironmentValue("FIREBASE_CLIENT_EMAIL"),
                  privateKey: requiredEnvironmentValue(
                    "FIREBASE_PRIVATE_KEY",
                  ).replace(/\\n/g, "\n"),
                }),
                projectId,
              });
      const decoded = await getAuth(app).verifyIdToken(token, !usingAuthEmulator);
      return { uid: decoded.uid };
    },
  };
}
