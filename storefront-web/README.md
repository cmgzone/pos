# Piki POS Storefront

A premium dark-themed Next.js storefront for every Piki POS business. Served as a static export by the backend at each business subdomain (e.g. `https://myshop.pikipos.com`) or via the legacy catalog link (`https://pikipos.com/catalog/<businessId>`).

The backend resolves the business from the request host (or path), injects SEO/OG meta and a `window.__STOREFRONT__` bootstrap hook into the built `index.html`, and serves the static assets from `/storefront/`. The SPA then fetches the catalog JSON from the existing public catalog endpoints and hydrates the store UI.

## Features

- Dark premium design with smooth, subtle Framer Motion animations
- Brand header with logo, cover, tagline, description and primary color theming
- Works for any business — products, services, or both
- Search, sort, category filters and multi-branch selector
- Animated product & service cards with quick-view modals
- Variant selection for products with multiple options
- Cart drawer with quantity controls
- Checkout with pickup/delivery fulfillment
- Order tracking by order number + phone
- Mobile responsive with floating cart button

## Tech stack

- Next.js 16 (App Router, static export)
- React 19 + TypeScript
- Tailwind CSS v4
- Framer Motion
- Lucide icons

## Local development

Install dependencies and start the dev server:

```bash
cd storefront-web
npm install
npm run dev
```

The dev server runs on `http://localhost:3000` by default and proxies `/api` to the backend when the backend is running on `http://localhost:3000`. If your backend runs on a different port, update `next.config.ts` or use the fetch base path in `lib/api.ts`.

For subdomain testing locally, add a hosts entry:

```
127.0.0.1 myshop.pikipos.com
```

Then visit:

```
http://myshop.pikipos.com:3000
```

Without a subdomain, use the legacy link directly:

```
http://localhost:3000/catalog/<businessId>
```

## Production build

The storefront is built into `storefront-web/dist/` and served by the backend from `/storefront/`:

```bash
cd storefront-web
npm install
npm run build
```

The backend (see root `Dockerfile`) serves the generated static files and falls back to the legacy inline renderer if the build is missing.
