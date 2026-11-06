FROM node:22-alpine

WORKDIR /app/gateway
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force
COPY src ./src

# Café docs are mounted (locally) or read from S3 (on AWS); they are not baked into the image.
ENV NODE_ENV=production PORT=8080 CONTENT_DIR=/app/content
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "src/server.js"]
