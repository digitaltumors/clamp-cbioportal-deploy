ARG CBIOPORTAL_BASE=docker.io/cbioportal/cbioportal:6.4.5@sha256:96809f5607be1fa02177faae2219d8cd61bb23c6ef79b8e05ba286606ae94b6c
ARG MAVEN_BUILDER=docker.io/library/maven:3-eclipse-temurin-21@sha256:c2a2c58516d160f43b50f12baa427ca86989e0bc942609e04aff61da5d9a7d74
ARG CBIOPORTAL_SOURCE_COMMIT=d9b76e4f5b981b686895517d1574f714180bfef0
FROM ${MAVEN_BUILDER} AS build
ARG CBIOPORTAL_SOURCE_COMMIT
WORKDIR /src
RUN git clone https://github.com/cBioPortal/cbioportal.git . \
    && git checkout --detach "${CBIOPORTAL_SOURCE_COMMIT}" \
    && test "$(git rev-parse HEAD)" = "${CBIOPORTAL_SOURCE_COMMIT}"
COPY security-dependencies.patch /tmp/security-dependencies.patch
RUN git apply --check /tmp/security-dependencies.patch \
    && git apply /tmp/security-dependencies.patch \
    && cp src/main/resources/application.properties.EXAMPLE src/main/resources/application.properties \
    && mvn -B package -DskipTests \
    && mkdir -p target/dependency \
    && cd target/dependency \
    && jar -xf ../cbioportal-exec.jar

FROM ${CBIOPORTAL_BASE}

USER root
COPY security-requirements.txt /tmp/security-requirements.txt
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get purge -y linux-libc-dev \
    && python3 -m pip install --break-system-packages --no-cache-dir --require-hashes -r /tmp/security-requirements.txt \
    && rm -f /tmp/security-requirements.txt /usr/bin/pebble /core/core-1.0.16.jar \
    && rm -rf /cbioportal-webapp/lib /cbioportal-webapp/META-INF /cbioportal-webapp/org \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/dependency/BOOT-INF/lib /cbioportal-webapp/lib
COPY --from=build /src/target/dependency/META-INF /cbioportal-webapp/META-INF
COPY --from=build /src/target/dependency/BOOT-INF/classes /cbioportal-webapp
RUN rm -f /cbioportal-webapp/lib/clickhouse-jdbc-*-all.jar

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP cBioPortal" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

COPY application.properties /cbioportal-webapp/application.properties
COPY images/Quartet_title.png /cbioportal-webapp/images/Quartet_title.png

# The upstream 6.4.5 image's launcher uses the v7 package name. The pinned
# maintenance-v6 source tree still exposes org.cbioportal.PortalApplication.
# Its entrypoint also assumes a WAR-style WEB-INF tree, which is not present in
# the executable-JAR layout copied above.
ENTRYPOINT []
CMD ["sh", "-c", "exec java ${JAVA_OPTS:-} -cp '/cbioportal-webapp:/cbioportal-webapp/lib/*' org.cbioportal.PortalApplication ${WEBAPP_OPTS:-}"]
