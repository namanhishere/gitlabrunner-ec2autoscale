#!/bin/bash
# Refresh the baked CI image to :latest on instance boot. The image layers are
# already present from the AMI, so this only downloads changed layers.
# It must never block boot or fail the instance, so all errors are non-fatal.
set -uo pipefail

IMAGE="$(cat /etc/gitlab-runner/ci-image 2>/dev/null || true)"
if [ -z "${IMAGE}" ]; then
  echo "pull-ci-image: no /etc/gitlab-runner/ci-image configured; nothing to do."
  exit 0
fi

echo "pull-ci-image: refreshing ${IMAGE}"
for attempt in 1 2 3 4 5; do
  if docker pull "${IMAGE}"; then
    echo "pull-ci-image: ${IMAGE} up to date."
    exit 0
  fi
  echo "pull-ci-image: attempt ${attempt} failed; retrying in 5s..." >&2
  sleep 5
done

echo "pull-ci-image: could not refresh ${IMAGE}; continuing with the baked copy." >&2
exit 0
