ARG CBIOPORTAL_BASE=cbioportal/cbioportal:6.4.5@sha256:96809f5607be1fa02177faae2219d8cd61bb23c6ef79b8e05ba286606ae94b6c
FROM ${CBIOPORTAL_BASE}

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get purge -y linux-libc-dev \
    && printf '%s\n' 'PyMySQL==1.1.1 --hash=sha256:4de15da4c61dc132f4fb9ab763063e693d521a80fd0e87943b9a453dd4c19d6c' > /tmp/security-requirements.txt \
    && python3 -m pip install --break-system-packages --no-cache-dir --require-hashes -r /tmp/security-requirements.txt \
    && rm -f /tmp/security-requirements.txt /usr/bin/pebble \
    && rm -rf /var/lib/apt/lists/*

ARG IMAGE_REVISION=unknown
LABEL org.opencontainers.image.title="CLAMP study loader" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

COPY study-loader/import-study.sh /usr/local/bin/import-study
RUN chmod 0555 /usr/local/bin/import-study

ENTRYPOINT ["/usr/local/bin/import-study"]
