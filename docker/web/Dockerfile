# 构建上下文：f2b-infra 的父目录
FROM node:22-bookworm-slim AS build

RUN corepack enable && corepack prepare pnpm@9.15.0 --activate

WORKDIR /workspace
COPY f2b-spec /workspace/f2b-spec
COPY f2b-web /workspace/f2b-web

WORKDIR /workspace/f2b-spec
RUN pnpm install --frozen-lockfile

WORKDIR /workspace/f2b-web
RUN pnpm install --frozen-lockfile

ENV F2B_SANDBOX_URL=http://sandbox:8787 \
    NEXT_TELEMETRY_DISABLED=1
RUN pnpm --filter @f2b/web build

FROM node:22-bookworm-slim AS runner
RUN corepack enable && corepack prepare pnpm@9.15.0 --activate

WORKDIR /workspace
COPY --from=build /workspace/f2b-spec /workspace/f2b-spec
COPY --from=build /workspace/f2b-web /workspace/f2b-web

ENV NODE_ENV=production \
    F2B_SANDBOX_URL=http://sandbox:8787 \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1

WORKDIR /workspace/f2b-web
EXPOSE 3000
CMD ["pnpm", "--filter", "@f2b/web", "start"]
