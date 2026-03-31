# --- 第一階段：編譯前端 Next.js ---
FROM node:22-bookworm AS frontend-builder

WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend ./
RUN npm run build

# --- 第二階段：編譯後端 Go ---
FROM golang:1.22-bookworm AS builder

WORKDIR /src
ARG TARGETOS=linux
ARG TARGETARCH=amd64

# 先複製依賴文件，利用 Docker layer cache 避免每次都重新下載套件
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 【關鍵修正】複製所有原始碼進入容器（包含根目錄的 main.go）
COPY . .

# 接收來自第一階段編譯好的前端靜態檔案
COPY --from=frontend-builder /frontend/out /src/static/admin

# 【關鍵修正】執行編譯，直接將編譯目標指向 ./main.go
# 並確保輸出路徑 /out/notion2api 資料夾存在（或直接輸出到該檔名）
RUN mkdir -p /out && \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -v -trimpath -ldflags="-s -w" -o /out/notion2api ./main.go

# --- 第三階段：最終運行環境 ---
FROM debian:bookworm-slim

ENV TZ=Asia/Taipei
WORKDIR /app

# 安裝運行時必要的基礎套件
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/config /app/data/notion_accounts /app/static

# 從 builder 階段複製編譯好的執行檔與靜態資源
COPY --from=builder /out/notion2api /app/notion2api
COPY --from=builder /src/static /app/static
COPY config.docker.json /app/config/config.default.json
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 根據 Dockerfile 原本設定開放 8787 Port
EXPOSE 8787

# 健康檢查
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8787/healthz || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["./notion2api", "--config", "/app/config/config.json"]
