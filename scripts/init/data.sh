#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing env file at ${ENV_FILE}"
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

: "${ELASTICSEARCH_URL:?ELASTICSEARCH_URL is required}"
: "${API_KEY:?API_KEY is required}"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required"
  exit 1
fi

ES_BASE="${ELASTICSEARCH_URL%/}"
BULK_REFRESH_VALUE="${BULK_REFRESH:-wait_for}"

auth_header="Authorization: ApiKey ${API_KEY}"

index_exists() {
  local index_name="$1"
  local status
  status="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "${auth_header}" \
    "${ES_BASE}/${index_name}")"
  [[ "${status}" == "200" ]]
}

create_index() {
  local index_name="$1"
  local mapping_file="$2"
  local payload

  payload="$(jq -c '{mappings: .}' "${mapping_file}")"

  curl -sS --fail \
    -X PUT "${ES_BASE}/${index_name}" \
    -H "${auth_header}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
}

index_count() {
  local index_name="$1"
  curl -sS --fail \
    -X GET "${ES_BASE}/${index_name}/_count" \
    -H "${auth_header}" | jq -r '.count // 0'
}

bulk_ingest_if_empty() {
  local index_name="$1"
  local ndjson_file="$2"
  local current_count
  local bulk_file
  local response_file

  current_count="$(index_count "${index_name}")"
  if [[ "${current_count}" != "0" ]]; then
    echo "Skipping bulk ingest for ${index_name}; current doc count is ${current_count}."
    return 0
  fi

  bulk_file="$(mktemp)"
  response_file="$(mktemp)"
  trap 'rm -f "${bulk_file}" "${response_file}"' EXIT

  awk -v idx="${index_name}" 'NF { print "{\"index\":{\"_index\":\"" idx "\"}}"; print $0 }' \
    "${ndjson_file}" > "${bulk_file}"

  curl -sS --fail \
    -X POST "${ES_BASE}/_bulk?refresh=${BULK_REFRESH_VALUE}" \
    -H "${auth_header}" \
    -H "Content-Type: application/x-ndjson" \
    --data-binary @"${bulk_file}" > "${response_file}"

  if [[ "$(jq -r '.errors' "${response_file}")" != "false" ]]; then
    echo "ERROR: Bulk ingest reported item failures for ${index_name}"
    jq '.items[] | select(.index.error != null)' "${response_file}"
    exit 1
  fi

  rm -f "${bulk_file}" "${response_file}"
  trap - EXIT
  echo "Ingested data into ${index_name}."
}

ensure_index_with_data() {
  local index_name="$1"
  local mapping_file="$2"
  local data_file="$3"

  if index_exists "${index_name}"; then
    echo "Index ${index_name} already exists."
  else
    echo "Creating index ${index_name}."
    create_index "${index_name}" "${mapping_file}"
  fi

  bulk_ingest_if_empty "${index_name}" "${data_file}"
}

ensure_index_with_data \
  "global-clients" \
  "${REPO_ROOT}/mappings/global-clients.json" \
  "${REPO_ROOT}/data/clients.ndjson"

ensure_index_with_data \
  "transactions" \
  "${REPO_ROOT}/mappings/transactions.json" \
  "${REPO_ROOT}/data/transactions.ndjson"

ensure_index_with_data \
  "internal-policies" \
  "${REPO_ROOT}/mappings/internal-policies.json" \
  "${REPO_ROOT}/data/policies.ndjson"

ensure_index_with_data \
  "external-news" \
  "${REPO_ROOT}/mappings/external-news.json" \
  "${REPO_ROOT}/data/news.ndjson"

echo "Data initialization completed."
