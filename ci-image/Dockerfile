# CI job image published to GitHub Container Registry (GHCR).
#
# This is the image your GitLab CI jobs run inside on the autoscaled EC2
# instances. It is baked into the worker AMI (Packer) and refreshed to :latest
# on each instance boot, so keep it lean. Customize the installed tooling to
# match what your pipelines actually need.
FROM debian:bookworm-slim

# OCI labels so the package links back to this repo in GHCR.
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="GitLab CI job image (autoscaled EC2 runner)" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        unzip \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

CMD ["bash"]
