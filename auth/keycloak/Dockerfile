ARG KEYCLOAK_BASE=quay.io/keycloak/keycloak:26.7.3@sha256:ff4257d0d64efbe99ed1ddfaf07765cc3c36dc7518bf8324d41961327f441c54
FROM ${KEYCLOAK_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP local Keycloak fixture" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

USER 1000
