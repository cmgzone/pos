# Piki POS Sync Backend

Node.js + Express API for the POS cloud layer, backed by PostgreSQL with
optional Redis caching.

## Architecture

- Flutter app keeps working locally with SQLite.
- This backend handles cloud auth, license activation, and sync endpoints.
- PostgreSQL stores shared cloud data.
- Redis caches public storefront responses when `REDIS_URL` is configured.

For Coolify, create PostgreSQL and Redis using their one-click database
resources. Deploy the application separately, then set `DATABASE_URL` and
`REDIS_URL` to the resources' internal URLs. The container initializes the
PostgreSQL schema before starting the API.

## Stack

- Node.js
- Express
- PostgreSQL via `pg`
- Redis via `redis`

## Environment

Copy `.env.example` to `.env` and fill in your real values.

The backend accepts any of these database environment variables:

- `DATABASE_URL`
- `POSTGRES_URL`
- `NEON_DATABASE_URL` (legacy fallback during migration)

Required or recommended values:

```bash
PORT=3000
NODE_ENV=development
DATABASE_URL=postgresql://USER:PASSWORD@POSTGRES-HOST:5432/piki_pos
DATABASE_SSL=false
REDIS_URL=redis://:PASSWORD@REDIS-HOST:6379/0
REDIS_CACHE_TTL_SECONDS=30
LICENSE_SIGNING_SECRET=replace-with-a-long-random-secret
PLATFORM_ADMIN_EMAIL=admin@your-domain.example
PLATFORM_ADMIN_PASSWORD=change-me
PLATFORM_JWT_SECRET=replace-with-a-long-random-jwt-secret
PLATFORM_ALLOWED_ORIGINS=https://admin.your-domain.example,https://shop.your-domain.example
PUBLIC_BASE_URL=https://api.your-domain.example
PUBLIC_CATALOG_ROOT_DOMAIN=your-domain.example
GOOGLE_PLAY_PACKAGE_NAME=com.piki.pos
GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL=play-billing@your-project.iam.gserviceaccount.com
GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
PAYPAL_CLIENT_ID=your-paypal-client-id
PAYPAL_CLIENT_SECRET=your-paypal-client-secret
FLUTTERWAVE_SECRET_KEY=your-flutterwave-secret-key
FLUTTERWAVE_WEBHOOK_SECRET_HASH=replace-with-a-random-flutterwave-webhook-secret
MPESA_CALLBACK_SECRET=replace-with-a-long-random-callback-secret
PAYMENT_SECRETS_ENCRYPTION_KEY=replace-with-a-random-32-byte-base64-key
SERPAPI_API_KEY=your-serpapi-key # optional, enables Piki web search
SMTP_HOST=mailcow.your-domain.example
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=otp@mailcow.your-domain.example
SMTP_PASS=your-mailcow-app-password # powers OTP + Piki Cloud + landing contact emails
OTP_FROM_EMAIL="Piki POS <otp@mailcow.your-domain.example>"
PIKI_CLOUD_FROM_EMAIL="Piki POS <alerts@your-domain.example>"
```

In production, `PLATFORM_ALLOWED_ORIGINS` is required for browser CORS. Native
mobile clients without an `Origin` header are still accepted.
`MPESA_CALLBACK_SECRET` is required and must be included in the callback URL as
`?secret=...` when registering the URL with Safaricom.
`PAYMENT_SECRETS_ENCRYPTION_KEY` must be one stable random 32-byte key. Generate
it once with `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`,
store it in the deployment secret manager, and back it up separately. Changing
or losing it makes saved merchant credentials unreadable.

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

Windows subscriptions use PayPal hosted checkout, Flutterwave v3 hosted
checkout, or Flutterwave v4 direct card checkout in the app. In the platform
admin, select the Flutterwave API version enabled on the merchant account.
Flutterwave v4 requires the Client ID, Client Secret, and a valid
base64-encoded 32-byte Encryption Key.

Set `PUBLIC_BASE_URL` to this backend's public HTTPS origin so payment
authorization can return to the verification endpoints. Use PayPal's live API
base URL when moving out of sandbox. In Flutterwave Dashboard → Settings →
Webhooks, register
`https://your-api-host.example.com/api/subscription/flutterwave/webhook` and use
the same value as `FLUTTERWAVE_WEBHOOK_SECRET_HASH`. Save the gateway, run
**Test v4 Checkout Readiness**, and enable it after the credentials, API access,
public callback URL, and hash are ready. Webhook verification is an operational
status rather than a checkout prerequisite: the first valid HMAC-signed payment
event records verification automatically. Changing the callback URL or secret
hash resets that status, but checkout completion still requires an exact
server-to-server charge verification.

Flutterwave v4 direct checkout sends PAN, CVV, PIN, and AVS data through the
Piki app and backend for immediate encrypted forwarding. Never log or store
those values. Complete the applicable PCI DSS assessment with the acquirer or
QSA before enabling v4 direct card checkout in production.

Coolify production variables should include:

```bash
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://USER:PASSWORD@INTERNAL-POSTGRES-HOST:5432/piki_pos
DATABASE_SSL=false
REDIS_URL=redis://:PASSWORD@INTERNAL-REDIS-HOST:6379/0
REDIS_CACHE_TTL_SECONDS=30
LICENSE_SIGNING_SECRET=replace-with-a-long-random-secret
PLATFORM_ADMIN_EMAIL=admin@your-domain.example
PLATFORM_ADMIN_PASSWORD=change-me-to-a-strong-password
PLATFORM_JWT_SECRET=replace-with-a-long-random-jwt-secret
PLATFORM_ALLOWED_ORIGINS=https://your-api-host.example.com,https://admin.your-domain.example
PUBLIC_BASE_URL=https://your-api-host.example.com
PUBLIC_CATALOG_ROOT_DOMAIN=your-domain.example
GOOGLE_PLAY_PACKAGE_NAME=com.piki.pos
GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL=play-billing@your-project.iam.gserviceaccount.com
GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
PAYPAL_BASE_URL=https://api-m.paypal.com
PAYPAL_CLIENT_ID=your-live-paypal-client-id
PAYPAL_CLIENT_SECRET=your-live-paypal-client-secret
FLUTTERWAVE_BASE_URL=https://api.flutterwave.com/v3
FLUTTERWAVE_V4_BASE_URL=https://f4bexperience.flutterwave.com
FLUTTERWAVE_SECRET_KEY=your-live-flutterwave-secret-key
FLUTTERWAVE_CLIENT_ID=your-flutterwave-v4-client-id
FLUTTERWAVE_CLIENT_SECRET=your-flutterwave-v4-client-secret
FLUTTERWAVE_ENCRYPTION_KEY=your-flutterwave-encryption-key
FLUTTERWAVE_WEBHOOK_SECRET_HASH=replace-with-a-random-flutterwave-webhook-secret
MPESA_CALLBACK_URL=https://your-api-host.example.com/api/payments/mpesa/stk-callback?secret=replace-with-a-long-random-callback-secret
MPESA_CALLBACK_SECRET=replace-with-a-long-random-callback-secret
PAYMENT_SECRETS_ENCRYPTION_KEY=replace-with-a-random-32-byte-base64-key
```

### Move Existing Neon Data

Keep the application using Neon while the Coolify PostgreSQL resource is being
prepared. In the application terminal, set the source and target URLs and run:

```bash
SOURCE_DATABASE_URL='postgresql://...neon...?sslmode=require' \
TARGET_DATABASE_URL='postgresql://...coolify-internal.../piki_pos' \
MIGRATION_CONFIRM=copy-neon-to-coolify-postgres \
npm run db:migrate:postgres
```

After the command succeeds, change the application's `DATABASE_URL` to the
Coolify PostgreSQL internal URL and redeploy. Redis is cache-only and does not
need data copied from Neon.

## Local Setup

1. Copy `.env.example` to `.env`
2. Add your PostgreSQL connection string
3. Install dependencies

```bash
npm install
```

4. Initialize the PostgreSQL schema

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
- `GET /api/ai/cloud-settings`
- `PUT /api/ai/cloud-settings`

5. Verify the connection

```bash
npm run db:check
```

6. Start the API

```bash
npm run dev
```

## Flutter App Build Settings

The Flutter app should point to your deployed API host, not directly to PostgreSQL.

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

## Piki Cloud

The backend refreshes proactive Piki insights every 15 minutes by default, so
monitoring continues while the Windows or mobile app is closed. Managers can
enable opt-in alert emails from **Settings → Cloud Sync → Piki Cloud**. Alerts
are based on synced cloud data, are severity-filtered, and are throttled by the
configured cooldown; Piki Cloud never modifies business data. Configure
`SMTP_HOST`, `SMTP_USER`, `SMTP_PASS`, and `PIKI_CLOUD_FROM_EMAIL` before
enabling delivery.

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
