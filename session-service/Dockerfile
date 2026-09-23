ARG MAVEN_BUILDER=docker.io/library/maven:3-eclipse-temurin-21@sha256:c2a2c58516d160f43b50f12baa427ca86989e0bc942609e04aff61da5d9a7d74
ARG JAVA_RUNTIME_BASE=docker.io/eclipse-temurin:21-jre-alpine@sha256:974b08960c5d96694c780e65b2d5705268ab1e1ca1a0dd0caf4ba6c3fe34d699
ARG SESSION_SERVICE_SOURCE_COMMIT=2edf9dc3b98a821cc7f0202d15095eebfefe6874
FROM ${MAVEN_BUILDER} AS build
ARG SESSION_SERVICE_SOURCE_COMMIT
WORKDIR /src
RUN git clone https://github.com/cBioPortal/session-service.git . \
    && git checkout --detach "${SESSION_SERVICE_SOURCE_COMMIT}" \
    && test "$(git rev-parse HEAD)" = "${SESSION_SERVICE_SOURCE_COMMIT}"
COPY security-dependencies.patch /tmp/security-dependencies.patch
RUN git apply --check /tmp/security-dependencies.patch \
    && git apply /tmp/security-dependencies.patch \
    && mvn -B package -DskipTests -Dpackaging.type=jar
FROM ${JAVA_RUNTIME_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP session service" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

USER root
RUN apk upgrade --no-cache
COPY --from=build --chown=10001:10001 /src/target/session_service-0.6.5.jar /app.war
USER 10001:10001
ENTRYPOINT ["java", "-jar", "/app.war"]
