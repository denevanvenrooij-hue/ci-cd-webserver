FROM nginx:alpine

RUN apk add --no-cache git

# Default repo URL baked in at build time — override at runtime via GITHUB_REPO env var
ARG GITHUB_REPO
ENV GITHUB_REPO="https://github/denevanvenrooij-hue/ci-cd-webserver.git/"

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

EXPOSE 4001

ENTRYPOINT ["/entrypoint.sh"]
