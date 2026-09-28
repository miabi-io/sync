ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG VERSION=dev
LABEL org.opencontainers.image.title="miabi-sync" \
      org.opencontainers.image.description="rsync helper for Miabi location migrations" \
      org.opencontainers.image.source="https://github.com/miabi-io/sync" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}"

RUN apk add --no-cache rsync

CMD ["rsync", "--version"]
