ARG SESSION_SERVICE_BASE=docker.io/cbioportal/session-service:0.6.5@sha256:5be37b996297dc9ca2503988407e79377c09acec74d06c9b15a9ff5e95f966d3
ARG JAVA_RUNTIME_BASE=docker.io/eclipse-temurin:21-jre-alpine@sha256:974b08960c5d96694c780e65b2d5705268ab1e1ca1a0dd0caf4ba6c3fe34d699
FROM ${SESSION_SERVICE_BASE} AS upstream
FROM ${JAVA_RUNTIME_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP session service" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

USER root
RUN apk upgrade --no-cache
COPY --from=upstream --chown=10001:10001 /app.war /app.war
USER 10001:10001
ENTRYPOINT ["java", "-jar", "/app.war"]
