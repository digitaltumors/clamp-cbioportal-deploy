ARG CBIOPORTAL_BASE=cbioportal/cbioportal:6.4.1
FROM ${CBIOPORTAL_BASE}

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP cBioPortal" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

COPY application.properties /cbioportal-webapp/application.properties
COPY images/Quartet_title.png /cbioportal-webapp/images/Quartet_title.png
