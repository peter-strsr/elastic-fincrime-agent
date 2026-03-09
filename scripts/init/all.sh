#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing env file at ${ENV_FILE}"
  echo "Create it first, for example: cp .env.example .env"
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

: "${ELASTICSEARCH_URL:?ELASTICSEARCH_URL is required}"
: "${KIBANA_URL:?KIBANA_URL is required}"
: "${API_KEY:?API_KEY is required}"

for required_cmd in curl jq awk; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    echo "ERROR: ${required_cmd} is required but not installed."
    exit 1
  fi
done

echo "==> Initializing data"
"${SCRIPT_DIR}/data.sh"

echo "==> Initializing tools"
"${SCRIPT_DIR}/tools.sh"

echo "==> Initializing agents"
"${SCRIPT_DIR}/agents.sh"

echo "Bootstrap completed successfully."
