ARG CBIOPORTAL_BASE=cbioportal/cbioportal:6.4.1
FROM ${CBIOPORTAL_BASE}

ARG IMAGE_REVISION=unknown
ARG STUDY_VERSION=unknown
LABEL org.opencontainers.image.title="CLAMP study loader" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.clamp.study.id="clamp_2026" \
      org.clamp.study.version="${STUDY_VERSION}"

COPY studies/clamp_2026 /study/clamp_2026
COPY study-loader/import-study.sh /usr/local/bin/import-study
RUN chmod 0555 /usr/local/bin/import-study \
    && find /study/clamp_2026 -type d -exec chmod 0555 {} + \
    && find /study/clamp_2026 -type f -exec chmod 0444 {} +

ENTRYPOINT ["/usr/local/bin/import-study"]
