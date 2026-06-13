FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache postgresql-client

ENV NODE_ENV=production
ENV PORT=3000

COPY backend/package*.json ./backend/
RUN cd backend && npm ci --omit=dev

COPY backend ./backend
COPY landing-page ./landing-page

WORKDIR /app/backend

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3000) + '/api/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["sh", "-c", "npm run db:init && exec node src/server.js"]
