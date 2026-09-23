ARG MAVEN_BUILDER=docker.io/library/maven:3-eclipse-temurin-21@sha256:c2a2c58516d160f43b50f12baa427ca86989e0bc942609e04aff61da5d9a7d74
ARG KEYCLOAK_BASE=quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c

FROM ${MAVEN_BUILDER} AS security-dependencies
WORKDIR /deps
COPY security-dependencies.pom pom.xml
RUN mvn -B dependency:copy-dependencies -DincludeScope=runtime -DoutputDirectory=/patched \
    && test -f /patched/netty-handler-4.1.137.Final.jar \
    && test -f /patched/bcprov-jdk18on-1.85.jar \
    && mkdir /empty \
    && jar --create --file /patched/empty-mssql-driver.jar -C /empty .

FROM ${KEYCLOAK_BASE}

USER root
# Quarkus' existing augmentation data references these paths during `kc.sh build`.
# Preserve the filenames while replacing their contents; Trivy reads the patched
# Maven metadata from inside each JAR and therefore reports the actual versions.
COPY --from=security-dependencies /patched/netty-handler-4.1.137.Final.jar /opt/keycloak/lib/lib/main/io.netty.netty-handler-4.1.136.Final.jar
COPY --from=security-dependencies /patched/bcprov-jdk18on-1.85.jar /opt/keycloak/lib/lib/main/org.bouncycastle.bcprov-jdk18on-1.84.jar
COPY --from=security-dependencies /patched/bcprov-jdk18on-1.85.jar /opt/keycloak/bin/client/lib/bcprov-jdk18on-1.84.jar
RUN /opt/keycloak/bin/kc.sh build
# The local fixture uses Keycloak's embedded H2 database. start-dev still expects
# every path from the original augmentation model, so retain the path as an empty
# valid JAR rather than shipping the unused SQL Server driver implementation.
COPY --from=security-dependencies /patched/empty-mssql-driver.jar /opt/keycloak/lib/lib/main/com.microsoft.sqlserver.mssql-jdbc-13.2.1.jre11.jar

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP local Keycloak fixture" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

USER 1000
