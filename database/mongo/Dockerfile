ARG GOSU_BUILDER=docker.io/golang:1.27.1-alpine3.24@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125
ARG NODE_BUILDER=docker.io/library/node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1
ARG MONGO_BASE=docker.io/mongo:7.0.41@sha256:b096b4cb9269f3ebcf363be63f1c50920f786879d03a1890347a3bf33f1f0df0
FROM ${GOSU_BUILDER} AS gosu-builder
RUN CGO_ENABLED=0 go install github.com/tianon/gosu@v0.0.0-20250923190938-6456aaa0f3c8

FROM ${NODE_BUILDER} AS js-yaml-builder
WORKDIR /src
RUN npm pack --ignore-scripts js-yaml@3.15.2 \
    && tar -xzf js-yaml-3.15.2.tgz

FROM ${MONGO_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP MongoDB" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        --only-upgrade mongodb-database-tools mongodb-mongosh \
    && rm -rf /var/lib/apt/lists/*
COPY --from=gosu-builder /go/bin/gosu /usr/local/bin/gosu
COPY --from=js-yaml-builder /src/package /opt/js-yaml
COPY --from=js-yaml-builder /src/package/dist/js-yaml.min.js /js-yaml.js
