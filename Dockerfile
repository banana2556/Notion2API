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

# 先複製依賴文件，利用快取優化構建速度
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 複製所有檔案（包含根目錄的 main.go）
COPY . .

# 將第一階段產出的靜態檔案放入後端預期路徑
COPY --from=frontend-builder /frontend/out /src/static/admin

# 執行編譯：--mount 必須緊跟在 RUN 之後，不能被 && 隔開
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -v -trimpath -ldflags="-s -w" -o /notion2api ./main.go

# --- 第三階段：最終運行環境 (輕量化) ---
FROM debian:bookworm-slim

# 設定時區
ENV TZ=Asia/Taipei
WORKDIR /app

# 安裝基本套件並清理快取以減少映像檔大小
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/config /app/data/notion_accounts /app/static

# 從 builder 複製編譯結果與靜態資源
COPY --from=builder /notion2api /app/notion2api
COPY --from=builder /src/static /app/static
COPY config.docker.json /app/config/config.default.json
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# 賦予 entrypoint 執行權限
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 開放連接埠
EXPOSE 8787

# 健康檢查：確認服務是否正常運作
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8787/healthz || exit 1

# 啟動指令
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["./notion2api", "--config", "/app/config/config.json"]
