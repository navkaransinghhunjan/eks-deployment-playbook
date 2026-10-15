# -------- Stage 1: Build Angular --------
FROM node:16-alpine AS angular-build
WORKDIR /app
# Install dependencies first (better layer caching)
COPY package*.json ./
RUN npm install --legacy-peer-deps
# Copy project files
COPY . .
# Increase memory + disable type checking for node_modules
ENV NODE_OPTIONS=--max_old_space_size=4096
# Patch docviewhelper's broken type declaration before building
# Strips all "type " modifiers from the export line in index.d.ts
RUN node -e "\
  const fs = require('fs');\
  const path = 'node_modules/docviewhelper/index.d.ts';\
  let c = fs.readFileSync(path, 'utf8');\
  c = c.replace(/export \{[^}]+\}/g, m => m.replace(/\btype /g, ''));\
  fs.writeFileSync(path, c);\
"
# Build Angular (Angular 12 compatible)
RUN npx ng build --configuration production
# -------- Stage 2: Nginx --------
# nginx-unprivileged, not nginx:alpine: it runs as uid 101 and listens on 8080, so the pod
# needs no root and no CAP_NET_BIND_SERVICE (install-log C1). default.conf listens on 8080
# to match.
FROM nginxinc/nginx-unprivileged:alpine
USER root
RUN rm -rf /usr/share/nginx/html/*
COPY --from=angular-build /app/dist/ /usr/share/nginx/html/
COPY default.conf /etc/nginx/conf.d/
COPY docker-entrypoint.sh /docker-entrypoint.d/99-<POOL>-env.sh
RUN chmod +x /docker-entrypoint.d/99-<POOL>-env.sh \
 && chown -R 101:101 /usr/share/nginx/html
USER 101

EXPOSE 8080

# ⚠️ The old CMD inlined `envsubst` and never invoked docker-entrypoint.sh, so the BASE_REF
# rewrite in that script NEVER RAN. Behind a path-prefixed route
# (<PUBLIC_HOST>/<repo>/eks) that leaves <base href="/"> and every asset 404s. The script
# now runs from /docker-entrypoint.d/, which the nginx image sources before starting.
CMD ["nginx", "-g", "daemon off;"]
