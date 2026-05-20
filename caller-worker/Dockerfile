FROM node:20-bullseye-slim AS build
WORKDIR /app

COPY caller-worker/package.json ./package.json
COPY caller-worker/tsconfig.json ./tsconfig.json
COPY caller-worker/iii-sdk ./iii-sdk
COPY caller-worker/src ./src
RUN npm install --no-audit --no-fund && npm run build

FROM node:20-bullseye-slim
WORKDIR /app
ENV NODE_ENV=production

COPY caller-worker/package.json ./package.json
COPY caller-worker/iii-sdk ./iii-sdk
RUN npm install --omit=dev --no-audit --no-fund
COPY --from=build /app/dist ./dist

EXPOSE 3111
CMD ["node", "dist/worker.js"]