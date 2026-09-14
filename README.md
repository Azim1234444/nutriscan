# NutriScan

NutriScan is a Flutter food-tracking app. Firebase Authentication and Cloud
Firestore remain the identity and persistence layers. Food-image analysis is
served separately by the Vercel function at `POST /api/analyze-food`.

## Vercel food-analysis API

The API accepts the same JSON payload as the retained Firebase callable:

```json
{
  "imageBase64": "<base64 image bytes without a data URL prefix>",
  "mimeType": "image/jpeg"
}
```

Every request must include the current Firebase ID token as
`Authorization: Bearer <token>`. The server verifies the token, validates the
image (JPEG, PNG or WebP; maximum 3 MiB decoded), applies per-user limits, then
calls Gemini. The Firebase Functions implementation under `functions/` is
intentionally retained during migration.

Configure these server-only variables in Vercel for Development, Preview, and
Production as appropriate:

- `GEMINI_API_KEY`
- `FIREBASE_PROJECT_ID` (`nutriscan-a66ae` for the current project)
- `FIREBASE_CLIENT_EMAIL` (service-account client email)
- `FIREBASE_PRIVATE_KEY` (the PEM private key; Vercel may store embedded
  newlines or escaped `\\n` newlines)
- `UPSTASH_REDIS_REST_URL`
- `UPSTASH_REDIS_REST_TOKEN`

The Firebase service-account values must be stored only in Vercel environment
variables, never in this repository. The Redis variables connect a persistent
Upstash store used for the 10 scans/hour and 30 scans/day limits per Firebase
user. The endpoint fails closed if that store is unavailable; an in-memory
serverless limiter would not be reliable across instances.

For Flutter, supply the one public backend setting at run/build time:

```text
--dart-define=NUTRISCAN_API_BASE_URL=https://your-vercel-domain.example
```

For local `vercel dev`, use a host reachable by the target device. Android
emulators normally need `http://10.0.2.2:3000`; desktop targets can use
`http://127.0.0.1:3000`. No Gemini or service-account secret is compiled into
Flutter. When Flutter is also using the Firebase Auth emulator, set
`FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099` only in the local backend
environment; do not set it in Vercel. In that mode the backend needs
`FIREBASE_PROJECT_ID` but does not require production service-account
credentials.

Backend checks:

```text
npm run backend:typecheck
npm run backend:lint
npm run backend:test
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
