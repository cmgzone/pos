# Piki POS Storefront

React + Vite storefront for each business's public online store. One SPA,
served per business subdomain (e.g. `https://myshop.pikipos.com`) or via the
legacy catalog link (`https://pikipos.com/catalog/<businessId>`).

The backend resolves the business from the request host (or path), injects
SEO/OG meta and a `window.__STOREFRONT__` bootstrap hook into the built
`index.html`, and serves the SPA assets from `/storefront/`. The SPA then
fetches the catalog JSON from the existing public catalog endpoints and
hydrates the store UI.

## Features

- Brand header (logo/cover, name, tagline, description, brand color theming)
- Search, sort, and category filters
- Product grid with images, variants, and availability chips
- Quick-view modal with variant selection
- Cart drawer with quantity controls and free-delivery progress bar
- Checkout (place order) and order tracking
- WhatsApp order confirmation link
- Branch selector for multi-branch businesses
- Mobile-responsive with a floating cart button

## Local Development

Run the backend on port `3000`, then start the storefront app:

```bash
npm install
npm run dev
```

Vite runs on port `4001` and proxies `/api` to `http://localhost:3000`.

For subdomain testing locally, point a business subdomain at your machine,
e.g. add this to your hosts file:

```
127.0.0.1 myshop.pikipos.com
```

and set `PUBLIC_CATALOG_ROOT_DOMAIN=pikipos.com` in `backend/.env`. Without a
subdomain, visit a legacy link directly:

```
http://localhost:4001/catalog/<businessId>
```

The SPA reads the business id from the `/catalog/<businessId>` path when no
`window.__STOREFRONT__` bootstrap is present.

## Production

The storefront is served by the backend on the same origin as the catalog API
(so subdomain routing keeps working). It is built and bundled into the backend
Docker image — see the root `Dockerfile`. There is no separate storefront
service to deploy.

To rebuild the bundle that the backend serves:

```bash
cd storefront-web
npm install
npm run build
```

The backend serves `storefront-web/dist/` from `/storefront/` and falls back
to the legacy inline renderer if the build is missing.
