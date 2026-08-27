ARG NGINX_BASE=nginx:1.27-alpine
FROM ${NGINX_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP web wrapper" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

COPY nginx.conf /etc/nginx/nginx.conf
COPY site/ /usr/share/nginx/html/test/
