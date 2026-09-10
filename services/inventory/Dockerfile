FROM node:20.13.1-alpine3.19 AS builder
WORKDIR /app
COPY package.json ./
RUN npm install --production --ignore-scripts && mkdir -p /app/node_modules

FROM gcr.io/distroless/nodejs20-debian12:nonroot
USER 65532:65532
WORKDIR /app
COPY --from=builder /app/node_modules /app/node_modules
COPY server.js ./
COPY package.json ./
EXPOSE 8081
ENTRYPOINT ["/nodejs/bin/node", "server.js"]
