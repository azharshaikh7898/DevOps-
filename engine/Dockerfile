FROM node:20-bullseye-slim
WORKDIR /app

COPY engine/package.json ./package.json
RUN npm install --no-audit --no-fund
COPY engine/index.js ./index.js
COPY deploy ./deploy

EXPOSE 3111 49134
CMD ["npm", "start"]