# ============================================================
# Multi-stage build - Simply Imóveis Frontend
# ============================================================

# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app

COPY package.json bun.lock* package-lock.json* ./
RUN npm ci --no-audit --no-fund 2>/dev/null || npm install

COPY . .

ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_PUBLISHABLE_KEY

ENV VITE_SUPABASE_URL=${VITE_SUPABASE_URL}
ENV VITE_SUPABASE_PUBLISHABLE_KEY=${VITE_SUPABASE_PUBLISHABLE_KEY}

RUN npm run build

# Stage 2: Serve with Nginx
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY docker/nginx-frontend.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
