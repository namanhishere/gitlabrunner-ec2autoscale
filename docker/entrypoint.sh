#!/bin/sh
set -eu

CONFIG_DIR="/etc/gitlab-runner"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
TEMPLATE="/config.toml.tpl"
SSH_KEY="/home/gitlab-runner/.ssh/ec2-key.pem"

echo "==> Rendering ${CONFIG_FILE} from template"

# Fail fast on the essentials so misconfiguration surfaces immediately.
: "${CI_SERVER_URL:?CI_SERVER_URL is required}"
: "${RUNNER_TOKEN:?RUNNER_TOKEN is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${ASG_NAME:?ASG_NAME is required}"

# Defaults for optional tuning knobs (also defaulted in .env.example).
export CONCURRENT="${CONCURRENT:-10}"
export MAX_INSTANCES="${MAX_INSTANCES:-10}"
export IDLE_COUNT="${IDLE_COUNT:-0}"
export IDLE_TIME="${IDLE_TIME:-20m0s}"
export SSH_USER="${SSH_USER:-ec2-user}"
export CI_IMAGE="${CI_IMAGE:-alpine:latest}"

mkdir -p "${CONFIG_DIR}"

# The official gitlab-runner image does not ship `envsubst`. Install it once
# (works for both the Ubuntu-based default image and the Alpine variant).
if ! command -v envsubst >/dev/null 2>&1; then
  echo "==> envsubst not found; installing gettext"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq gettext-base
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache gettext
  else
    echo "ERROR: cannot install envsubst (no apt-get or apk found)." >&2
    exit 1
  fi
fi

# Render only the variables we control, leaving any other $ sequences intact.
# The single-quoted list is envsubst's SHELL-FORMAT argument; the vars must NOT
# be expanded by the shell here, so SC2016 is a false positive.
# shellcheck disable=SC2016
envsubst '${CONCURRENT} ${CI_SERVER_URL} ${RUNNER_TOKEN} ${MAX_INSTANCES} ${ASG_NAME} ${AWS_REGION} ${SSH_USER} ${IDLE_COUNT} ${IDLE_TIME} ${CI_IMAGE}' \
  < "${TEMPLATE}" > "${CONFIG_FILE}"

# Secure the SSH private key if it was mounted.
if [ -f "${SSH_KEY}" ]; then
  chmod 600 "${SSH_KEY}" 2>/dev/null || true
  echo "==> SSH key present at ${SSH_KEY}"
else
  echo "WARNING: SSH key not found at ${SSH_KEY}; the connector will not be able to reach instances." >&2
fi

echo "==> Installing fleeting plugin(s) referenced in config.toml"
gitlab-runner fleeting install --config "${CONFIG_FILE}"

echo "==> Starting GitLab Runner"
exec gitlab-runner run --working-directory "${CONFIG_DIR}" --config "${CONFIG_FILE}"
