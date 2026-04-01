# --- 第一階段：編譯前端 Next.js 靜態檔案 ---
FROM node:22-bookworm AS frontend-builder

WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend ./
RUN npm run build

# --- 第二階段：編譯後端 Go 執行檔 ---
FROM golang:1.22-bookworm AS builder

WORKDIR /src
ARG TARGETOS=linux
ARG TARGETARCH=amd64

# 複製依賴並下載
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 複製所有程式碼
COPY . .

# 接收前端靜態檔案
COPY --from=frontend-builder /frontend/out /src/static/admin

# 【核心修正】將編譯目標指向正確的子目錄路徑 cmd/notion2api
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -v -trimpath -ldflags="-s -w" -o /notion2api ./cmd/notion2api

# --- 第三階段：最終運行環境 ---
FROM debian:bookworm-slim

ENV TZ=Asia/Taipei
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/config /app/data/notion_accounts /app/static

# 複製執行檔與資源
COPY --from=builder /notion2api /app/notion2api
COPY --from=builder /src/static /app/static
COPY config.docker.json /app/config/config.default.json
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8787/healthz || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["./notion2api", "--config", "/app/config/config.json"]
