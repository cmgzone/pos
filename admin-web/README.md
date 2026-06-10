# Piki POS Admin Panel

React + Vite admin portal for the Piki POS platform.

## Local Development

Run the backend on port `3000`, then start the admin app:

```bash
npm install
npm run dev
```

Vite proxies `/api` to `http://localhost:3000` during development.

## Coolify Deployment

Deploy this `admin-web` folder with its `Dockerfile`.

Set one of these environment variables on the admin service:

```bash
BACKEND_URL=https://pikipos.com
```

or:

```bash
PIKI_API_BASE_URL=https://pikipos.com
```

`BACKEND_URL` configures the nginx `/api` proxy. `PIKI_API_BASE_URL` also
exposes a runtime browser config so the React app can call the backend directly.

On the backend service, make sure CORS allows the admin domain if direct API
calls are used:

```bash
PLATFORM_ALLOWED_ORIGINS=https://admin.pikipos.com,https://pikipos.com
```
