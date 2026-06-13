# Piki POS Sync Backend

Node.js + Express API for the POS cloud layer, backed by Neon Postgres.

## Architecture

- Flutter app keeps working locally with SQLite.
- This backend handles cloud auth, license activation, and sync endpoints.
- Neon is the hosted PostgreSQL database for shared cloud data.

Neon is the database only. You still deploy this API separately on a host such
as Render, Railway, Fly.io, or your own server.

For Coolify, deploy the repository root with the included `Dockerfile`. The
container runs this backend, serves the landing page from `/`, and exposes port
`3000`.

## Stack

- Node.js
- Express
- Neon Postgres via `@neondatabase/serverless`

## Environment

Copy `.env.example` to `.env` and fill in your real values.

The backend accepts any of these database env vars:

- `NEON_DATABASE_URL`
- `DATABASE_URL`
- `POSTGRES_URL`

Required or recommended values:

```bash
PORT=3000
NODE_ENV=development
NEON_DATABASE_URL=postgresql://USER:PASSWORD@YOUR-NEON-ENDPOINT/velora_pos?sslmode=require
LICENSE_SIGNING_SECRET=replace-with-a-long-random-secret
PLATFORM_ADMIN_EMAIL=admin@your-domain.example
PLATFORM_ADMIN_PASSWORD=change-me
PLATFORM_JWT_SECRET=replace-with-a-long-random-jwt-secret
PLATFORM_ALLOWED_ORIGINS=https://admin.your-domain.example,https://shop.your-domain.example
PUBLIC_BASE_URL=https://api.your-domain.example
PUBLIC_CATALOG_ROOT_DOMAIN=your-domain.example
GOOGLE_PLAY_PACKAGE_NAME=com.example.pos_app
GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL=play-billing@your-project.iam.gserviceaccount.com
GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
PAYPAL_CLIENT_ID=your-paypal-client-id
PAYPAL_CLIENT_SECRET=your-paypal-client-secret
FLUTTERWAVE_SECRET_KEY=your-flutterwave-secret-key
MPESA_CALLBACK_SECRET=replace-with-a-long-random-callback-secret
SERPAPI_API_KEY=your-serpapi-key # optional, enables Piki web search
```

In production, `PLATFORM_ALLOWED_ORIGINS` is required for browser CORS. Native
mobile clients without an `Origin` header are still accepted. If you set
`MPESA_CALLBACK_SECRET`, include it in the M-Pesa callback URL as
`?secret=...` or send it with the `X-M-Pesa-Callback-Secret` header.

For manual M-Pesa Till/Paybill matching, register these HTTPS URLs in Daraja
using the same secret:

```bash
https://your-api-host.example.com/api/payments/mpesa/c2b-validation?secret=replace-with-a-long-random-callback-secret
https://your-api-host.example.com/api/payments/mpesa/c2b-confirmation?secret=replace-with-a-long-random-callback-secret
```

For M-Pesa STK Push sale payments, use the POS callback URL below. Each shop
adds its own shortcode, consumer key, consumer secret, and passkey in the POS
Payment Methods settings. M-Pesa is not used for subscription billing.

Android subscriptions use Google Play Billing only. Create the product IDs
shown in the platform admin plan editor (for example
`piki_starter_monthly`) as subscriptions in Play Console, then give the
configured service account access to the Android Publisher API.

Windows subscriptions open PayPal or Flutterwave hosted checkout. Set
`PUBLIC_BASE_URL` to this backend's public HTTPS origin so those providers can
return to the verification endpoints. Use PayPal's live API base URL when
moving out of sandbox.

Coolify production variables should include:

```bash
NODE_ENV=production
PORT=3000
NEON_DATABASE_URL=postgresql://USER:PASSWORD@YOUR-NEON-ENDPOINT/piki_pos?sslmode=require
LICENSE_SIGNING_SECRET=replace-with-a-long-random-secret
PLATFORM_ADMIN_EMAIL=admin@your-domain.example
PLATFORM_ADMIN_PASSWORD=change-me-to-a-strong-password
PLATFORM_JWT_SECRET=replace-with-a-long-random-jwt-secret
PLATFORM_ALLOWED_ORIGINS=https://your-api-host.example.com,https://admin.your-domain.example
PUBLIC_BASE_URL=https://your-api-host.example.com
PUBLIC_CATALOG_ROOT_DOMAIN=your-domain.example
GOOGLE_PLAY_PACKAGE_NAME=com.example.pos_app
GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL=play-billing@your-project.iam.gserviceaccount.com
GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
PAYPAL_BASE_URL=https://api-m.paypal.com
PAYPAL_CLIENT_ID=your-live-paypal-client-id
PAYPAL_CLIENT_SECRET=your-live-paypal-client-secret
FLUTTERWAVE_BASE_URL=https://api.flutterwave.com/v3
FLUTTERWAVE_SECRET_KEY=your-live-flutterwave-secret-key
MPESA_CALLBACK_URL=https://your-api-host.example.com/api/payments/mpesa/stk-callback?secret=replace-with-a-long-random-callback-secret
MPESA_CALLBACK_SECRET=replace-with-a-long-random-callback-secret
```

## Local Setup

1. Copy `.env.example` to `.env`
2. Add your Neon pooled connection string
3. Install dependencies

```bash
npm install
```

4. Initialize the Neon schema

```bash
npm run db:init
```

This now creates the core sync tables and the platform AI tables used by:

- `GET /api/platform/ai-config`
- `PUT /api/platform/ai-config`
- `POST /api/platform/ai-test`
- `GET /api/ai/config`
- `POST /api/ai/chat`
- `POST /api/ai/web-search`

5. Verify the connection

```bash
npm run db:check
```

6. Start the API

```bash
npm run dev
```

## Flutter App Build Settings

The Flutter app should point to your deployed API host, not directly to Neon.

Example:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://your-api-host.example.com/api \
  --dart-define=LICENSE_SIGNING_SECRET=replace-with-the-same-secret
```

Use `SOCKET_URL` too if you later add real-time features on a separate origin.

## Endpoints

- `GET /` serves the Piki POS landing page
- `GET /api/health`
- `GET /api/catalog/storefront?deviceId=<device id>`
- `GET /api/public/catalog` resolves the catalog from the request subdomain
- `POST /api/public/demo-requests`
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/license/activate`
- `POST /api/license/refresh`
- `GET /api/sync/status?cursor=<server revision>`
- `GET /api/sync/pull?cursor=<server revision>`
- `POST /api/sync/push`
- `POST /api/platform/login`
- `GET /api/platform/dashboard`
- `GET /api/platform/businesses`
- `GET /api/platform/users`
- `GET /api/platform/ai-config`
- `PUT /api/platform/ai-config`
- `POST /api/platform/ai-test`
- `GET /api/ai/config`
- `POST /api/ai/chat`
- `POST /api/ai/web-search`
- `POST /api/payments/mpesa/c2b-validation`
- `POST /api/payments/mpesa/c2b-confirmation`
- `POST /api/payments/mpesa/claim-c2b`

Legacy timestamp sync is also still supported through `since=<ISO timestamp>`.

## Conflict Rule

- Newest `updated_at` wins
- Stable UUID `id` values prevent duplicate inserts
- Soft deletes are represented with `deleted_at`
- The server owns `sync_status` and always stores/returns it as `synced`
- Safe incremental sync should use the server-owned revision `cursor`

## Cursor Sync

- New clients should start with `cursor=0`
- Each successful pull returns `nextCursor`
- The next pull should send that `nextCursor` back as `cursor`
- Push writes are serialized on the server so revision cursors stay safe for
  repeatable-read pull snapshots
