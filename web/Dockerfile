ARG NGINX_BASE=docker.io/nginx:1.31.5-alpine-slim@sha256:3b171d7224b669faa3cc2137fea0a65301791df1ec1f271ebd2a2b7461f7fade
FROM ${NGINX_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP web wrapper" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY portal-security-headers.conf /etc/nginx/portal-security-headers.conf
COPY site/ /usr/share/nginx/html/test/
USER 101:101
