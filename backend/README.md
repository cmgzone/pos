# Velora POS Sync Backend

Node.js + Neon backend for syncing the local Flutter SQLite database to an online PostgreSQL store.

## Stack

- Node.js
- Express
- Neon Postgres via `@neondatabase/serverless`

## Endpoints

- `GET /api/health`
- `GET /api/sync/status?cursor=<server revision>`
- `GET /api/sync/status?since=<ISO timestamp>` for legacy timestamp polling
- `GET /api/sync/pull?cursor=<server revision>`
- `GET /api/sync/pull?since=<ISO timestamp>` for legacy timestamp pulls
- `POST /api/sync/push`

## Conflict Rule

- Newest `updated_at` wins
- Stable UUID `id` values prevent duplicate inserts
- Soft deletes are represented with `deleted_at`
- The server owns `sync_status` and always stores/returns it as `synced`
- Safe incremental sync should use the server-owned revision `cursor`, not device
  `updated_at` timestamps

## Local Setup

1. Copy `.env.example` to `.env`
2. Set `NEON_DATABASE_URL` to the connection string from your Neon project
3. Install dependencies:

```bash
npm install
```

4. Initialize the Neon schema from this repo:

```bash
npm run db:init
```

   The initializer runs `sql/init.sql` inside a transaction. It is safe to
   rerun after pulling schema changes because the SQL is written to be
   additive and idempotent where possible.

5. Optionally verify the connection:

```bash
npm run db:check
```

6. Start the server:

```bash
npm run dev
```

## Environment

`.env` is intended for local secrets only and should not be committed. The
backend expects:

```bash
PORT=3000
NODE_ENV=development
NEON_DATABASE_URL=postgres://user:password@ep-example.us-east-1.aws.neon.tech/velora_pos?sslmode=require
```

## Push Payload

```json
{
  "deviceId": "device-uuid",
  "changes": {
    "products": [
      {
        "id": "uuid",
        "name": "Sugar",
        "price": 2500,
        "updated_at": "2026-04-17T12:00:00.000Z"
      }
    ]
  }
}
```

## Pull Response

```json
{
  "ok": true,
  "serverTime": "2026-04-17T12:00:00.000Z",
  "cursor": "120",
  "nextCursor": "148",
  "data": {
    "products": []
  }
}
```

## Cursor Sync

- New clients should start with `cursor=0`
- Each successful pull returns `nextCursor`
- The next pull should send that `nextCursor` back as `cursor`
- Push writes are serialized on the server so revision cursors stay safe for
  repeatable-read pull snapshots

## Push Response Notes

- `received` is the raw number of rows the device sent per table
- `applied` is the number of inserts/updates written by the server
- `unchanged` is the number of rows that were already identical on the server
- `invalid` is the number of malformed rows rejected before write
- `conflictCount` and `conflicts` describe stale or same-timestamp conflicts
- `latestAppliedCursor` is the newest server revision written by that push, when
  at least one row was applied

Example conflict entry:

```json
{
  "id": "uuid",
  "reason": "stale_update",
  "incomingUpdatedAt": "2026-04-17T10:00:00.000Z",
  "serverUpdatedAt": "2026-04-17T12:00:00.000Z",
  "serverRow": {
    "id": "uuid",
    "name": "Sugar",
    "price": 2600,
    "updated_at": "2026-04-17T12:00:00.000Z",
    "sync_status": "synced"
  }
}
```

## Status Endpoint

- `GET /api/sync/status?cursor=<server revision>` adds a `changed_since` count
  per table using the safe server revision cursor and returns `snapshotCursor`
- `GET /api/sync/status?since=<ISO timestamp>` is still available for legacy
  timestamp polling when a cursor has not been adopted yet
