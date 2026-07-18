# Toolbox / dev container: AWS CLI, Terraform, Packer, Git and friends.
#
# Run it with `docker compose run --rm toolbox` to bootstrap, build the AMI,
# and run Terraform — all against the host's ~/.aws credentials (mounted in),
# so nothing is installed on the host and credentials stay in one place.
FROM debian:bookworm-slim

# Pin tool versions for reproducible builds.
ARG TERRAFORM_VERSION=1.9.8
ARG PACKER_VERSION=1.11.2

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        groff \
        jq \
        less \
        openssh-client \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (arch-aware).
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  AWS_ARCH=x86_64 ;; \
      aarch64) AWS_ARCH=aarch64 ;; \
      *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip

# Terraform + Packer from the official HashiCorp releases.
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" -o /tmp/terraform.zip; \
    unzip -q /tmp/terraform.zip -d /usr/local/bin; \
    curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${ARCH}.zip" -o /tmp/packer.zip; \
    unzip -q /tmp/packer.zip -d /usr/local/bin; \
    rm -f /tmp/terraform.zip /tmp/packer.zip; \
    terraform version; \
    packer version; \
    aws --version

WORKDIR /workspace
ENTRYPOINT ["/bin/bash"]
