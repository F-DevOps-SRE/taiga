# Taiga Events 6.10.0
FROM node:24-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force


FROM node:24-alpine

# Parches de seguridad del sistema base publicados después de la imagen oficial.
# npm/yarn/corepack no se usan en runtime: se eliminan para no arrastrar sus
# dependencias (y sus vulnerabilidades) a la imagen final.
RUN apk upgrade --no-cache \
    && rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
              /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NODE_ENV=production \
    WEB_SOCKET_SERVER_PORT=8888

EXPOSE 8888

CMD ["node", "./src/index.js"]
