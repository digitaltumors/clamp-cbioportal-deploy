ARG CBIOPORTAL_BASE=clamp-cbioportal:local
FROM ${CBIOPORTAL_BASE}

USER root

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP study loader" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

COPY study-loader/import-study.sh /usr/local/bin/import-study
RUN chmod 0555 /usr/local/bin/import-study

ENTRYPOINT ["/usr/local/bin/import-study"]
