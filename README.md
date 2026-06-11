# Piki POS

Piki POS is a Flutter point-of-sale app with:

- local-first SQLite storage for offline use
- a Node.js sync/auth backend
- Neon Postgres for cloud data

## Project Structure

- `lib/`: Flutter POS app
- `backend/`: Express API backed by Neon
- `admin-web/`: separate web admin frontend

## Neon Migration Notes

This project already uses Neon for the backend database. The important
production setup is:

1. Deploy the backend API somewhere reachable from the app
2. Point that backend at Neon with `NEON_DATABASE_URL`
3. Build the Flutter app with your API URL and matching license secret

Neon does not replace the Express API in this repo. It replaces the hosted
Postgres database behind that API.

## Run The Backend

See [backend/README.md](backend/README.md).

## Run The Flutter App

Example:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://pikipos.com/api \
  --dart-define=LICENSE_SIGNING_SECRET=replace-with-the-same-secret
```

If you do not pass `API_BASE_URL`, the app falls back to the current default
host baked into the build: `https://pikipos.com/api`.
