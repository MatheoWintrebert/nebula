# syntax=docker/dockerfile:1
FROM node:24.21-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:24.21-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=3000
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ENV APP_VERSION=$APP_VERSION
LABEL org.opencontainers.image.version=$APP_VERSION org.opencontainers.image.revision=$GIT_SHA
COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
USER node
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=3 \
  CMD ["node","-e","require('node:http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]
# sur SIGTERM, servir encore 8 s le temps que Traefik retire le replica
CMD ["sh","-c","node src/index.js & pid=$!; trap 'sleep 8; kill -TERM $pid' TERM INT; wait $pid; trap - TERM INT; wait $pid"]
