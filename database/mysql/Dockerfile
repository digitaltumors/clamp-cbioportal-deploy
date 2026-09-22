ARG GOSU_BUILDER=docker.io/golang:1.27.1-alpine3.24@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125
ARG MYSQL_BASE=docker.io/mysql:8.0.46@sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b
FROM ${GOSU_BUILDER} AS gosu-builder
RUN CGO_ENABLED=0 go install github.com/tianon/gosu@v0.0.0-20250923190938-6456aaa0f3c8

FROM ${MYSQL_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP MySQL" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

USER root
RUN microdnf update -y \
    && microdnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum \
        /usr/bin/mysqlsh /usr/lib/mysqlsh
COPY --from=gosu-builder /go/bin/gosu /usr/local/bin/gosu
