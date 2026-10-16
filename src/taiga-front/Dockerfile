# Taiga Front 6.10.3
FROM node:16.19.1-bullseye AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

RUN npx gulp deploy

# The frontend reads this file at runtime. For local Docker development we
# deliberately point it to the single gateway exposed on localhost:9000.
RUN cp conf/conf.example.json dist/conf.json \
    && node -e "const fs=require('fs'); const p='dist/conf.json'; const c=JSON.parse(fs.readFileSync(p)); c.api='http://localhost:9000/api/v1/'; c.eventsUrl='ws://localhost:9000/events'; c.baseHref='/'; fs.writeFileSync(p, JSON.stringify(c,null,2));"

FROM nginx:1.30-alpine

# Parches de seguridad del sistema base publicados después de la imagen oficial.
RUN apk upgrade --no-cache

COPY docker/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
