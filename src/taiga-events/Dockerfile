# Taiga Events 6.10.0
FROM node:16.19.1-bullseye-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY . .

ENV NODE_ENV=production \
    WEB_SOCKET_SERVER_PORT=8888

EXPOSE 8888

CMD ["npm", "run", "start:production"]
