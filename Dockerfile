FROM node:22-bookworm AS frontend-builder

WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend ./
RUN npm run build

FROM golang:1.22-bookworm AS builder

WORKDIR /src
ARG TARGETOS=linux
ARG TARGETARCH=amd64
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

COPY cmd ./cmd
COPY internal ./internal
COPY static ./static
COPY --from=frontend-builder /frontend/out /src/static/admin
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    test -f ./main.go \
    && CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -v -trimpath -ldflags="-s -w" -o /out/notion2api ./main.go

FROM debian:bookworm-slim

ENV TZ=Asia/Shanghai
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/config /app/data/notion_accounts /app/static

COPY --from=builder /out/notion2api /app/notion2api
COPY --from=builder /src/static /app/static
COPY config.docker.json /app/config/config.default.json
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD curl -fsS http://127.0.0.1:8787/healthz || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["./notion2api", "--config", "/app/config/config.json"]
