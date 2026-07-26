# Monorepo NeoForma — contexte = racine du repo
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
COPY apps/worker/package.json apps/worker/
COPY packages/shared/package.json packages/shared/
COPY packages/neoscore/package.json packages/neoscore/
RUN npm install

FROM deps AS api
WORKDIR /app
COPY packages ./packages
COPY apps/api ./apps/api
WORKDIR /app/apps/api
RUN npx prisma generate
RUN chmod +x docker-entrypoint.sh
ENV NODE_ENV=production
EXPOSE 3001
# Migre puis démarre (voir docker-entrypoint.sh)
CMD ["./docker-entrypoint.sh"]

# Worker async — SMS / alertes / Mobile Money (file Redis neoforma:jobs)
FROM deps AS worker
WORKDIR /app
COPY packages ./packages
COPY apps/api ./apps/api
COPY apps/worker ./apps/worker
WORKDIR /app/apps/worker
ENV NODE_ENV=production
CMD ["npx", "tsx", "src/main.ts"]

FROM deps AS web-build
ARG VITE_API_URL=
ENV VITE_API_URL=$VITE_API_URL
COPY packages ./packages
COPY apps/web ./apps/web
RUN npm run build --workspace=@neoforma/web

FROM nginx:1.27-alpine AS web
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=web-build /app/apps/web/dist /usr/share/nginx/html
EXPOSE 80
