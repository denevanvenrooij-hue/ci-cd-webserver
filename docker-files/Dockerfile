FROM nginx:alpine

RUN apk add --no-cache git

# ── oauth2-proxy binary ──────────────────────────────────────────────────────
ARG OAUTH2_PROXY_VERSION=v7.15.2
RUN wget -q "https://github.com/oauth2-proxy/oauth2-proxy/releases/download/${OAUTH2_PROXY_VERSION}/oauth2-proxy-${OAUTH2_PROXY_VERSION}.linux-amd64.tar.gz" \
         -O /tmp/oauth2-proxy.tar.gz \
    && tar -xzf /tmp/oauth2-proxy.tar.gz -C /tmp \
    && mv /tmp/oauth2-proxy-${OAUTH2_PROXY_VERSION}.linux-amd64/oauth2-proxy /usr/local/bin/oauth2-proxy \
    && chmod +x /usr/local/bin/oauth2-proxy \
    && rm -rf /tmp/oauth2-proxy*

# Static oauth2-proxy config — secrets are supplied at runtime via env vars
ENV OAUTH2_PROXY_PROVIDER=google \
    OAUTH2_PROXY_EMAIL_DOMAINS=ubiops.com \
    OAUTH2_PROXY_UPSTREAM=file:///dev/null \
    OAUTH2_PROXY_HTTP_ADDRESS=127.0.0.1:4180 \
    OAUTH2_PROXY_REVERSE_PROXY=true \
    OAUTH2_PROXY_COOKIE_SECURE=false

# ── site config ─────────────────────────────────────────────────────────────
# Default repo URL baked in at build time — override at runtime via GITHUB_REPO env var
ARG GITHUB_REPO
ENV GITHUB_REPO=${GITHUB_REPO}

ENV GITHUB_BRANCH="main"

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY nginx-main.conf /etc/nginx/nginx.conf

RUN mkdir -p /usr/share/nginx/html && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 777 /usr/share/nginx/html

RUN mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chmod -R 777 /var/cache/nginx && \
    chmod -R 777 /var/run

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
