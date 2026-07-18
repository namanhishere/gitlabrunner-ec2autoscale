#!/bin/bash
# Provisions the GitLab Runner worker AMI:
#  - Docker + common CI tools preinstalled
#  - CI image baked in at build time
#  - a boot-time systemd service that refreshes the CI image (:latest)
set -euxo pipefail

: "${CI_IMAGE:?CI_IMAGE must be set}"
: "${SSH_USER:=ec2-user}"

# --- Base tools + Docker ---
sudo dnf -y update
sudo dnf -y install docker git tar gzip unzip jq

sudo systemctl enable docker
sudo systemctl start docker

# Let the SSH user run docker without sudo (the runner connects as this user).
sudo usermod -aG docker "${SSH_USER}"

# --- Persist the CI image reference for the boot-time pull service ---
sudo mkdir -p /etc/gitlab-runner
echo "${CI_IMAGE}" | sudo tee /etc/gitlab-runner/ci-image >/dev/null

# --- Bake the CI image into the AMI (biggest cold-start win) ---
# Retry a few times in case the registry/network is briefly unavailable.
for attempt in 1 2 3; do
  if sudo docker pull "${CI_IMAGE}"; then
    break
  fi
  echo "docker pull attempt ${attempt} failed; retrying..." >&2
  sleep 5
done

# --- Install the boot-time refresh service ---
sudo install -m 0755 /tmp/pull-ci-image.sh /usr/local/bin/pull-ci-image.sh
sudo install -m 0644 /tmp/pull-ci-image.service /etc/systemd/system/pull-ci-image.service
sudo systemctl enable pull-ci-image.service

# --- Clean up build-time artifacts ---
rm -f /tmp/pull-ci-image.sh /tmp/pull-ci-image.service
sudo dnf clean all

echo "AMI provisioning complete. Baked CI image: ${CI_IMAGE}"
