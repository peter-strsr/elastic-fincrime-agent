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

: "${KIBANA_URL:?KIBANA_URL is required}"
: "${API_KEY:?API_KEY is required}"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required"
  exit 1
fi

KIBANA_BASE="${KIBANA_URL%/}"
SPACE_PATH=""
if [[ -n "${KIBANA_SPACE_ID:-}" ]]; then
  SPACE_PATH="/s/${KIBANA_SPACE_ID}"
fi

API_BASE="${KIBANA_BASE}${SPACE_PATH}/api/agent_builder"
auth_header="Authorization: ApiKey ${API_KEY}"

extract_value() {
  local prefix="$1"
  local file="$2"
  awk -F': ' -v pfx="${prefix}" '$1 == pfx {print $2; exit}' "${file}"
}

extract_custom_instructions() {
  local file="$1"
  awk '
    /^Custom instructions:/ {capture=1; next}
    capture {lines[++n]=$0}
    END {
      start=1
      while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++
      finish=n
      while (finish >= start && lines[finish] ~ /^[[:space:]]*$/) finish--
      for (i=start; i<=finish; i++) print lines[i]
    }
  ' "${file}"
}

tool_exists() {
  local tool_id="$1"
  local status
  status="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "${auth_header}" \
    "${API_BASE}/tools/${tool_id}")"
  [[ "${status}" == "200" ]]
}

submit_tool_request() {
  local method="$1"
  local endpoint="$2"
  local payload="$3"
  local verbose="${4:-1}"
  local response_file
  local status

  response_file="$(mktemp)"
  status="$(curl -sS \
    -o "${response_file}" \
    -w "%{http_code}" \
    -X "${method}" "${endpoint}" \
    -H "${auth_header}" \
    -H "kbn-xsrf: bootstrap" \
    -H "Content-Type: application/json" \
    -d "${payload}")"

  if [[ "${status}" =~ ^2 ]]; then
    rm -f "${response_file}"
    return 0
  fi

  if [[ "${verbose}" == "1" ]]; then
    echo "API ${method} ${endpoint} failed with status ${status}" >&2
    cat "${response_file}" >&2
  fi
  rm -f "${response_file}"
  return 1
}

build_payload() {
  local tool_id="$1"
  local pattern="$2"
  local custom_instructions="$3"
  local tool_type="$4"
  local pattern_key="$5"
  local custom_key="$6"
  local include_id="$7"
  local include_type="$8"

  local payload
  payload="$(jq -cn \
    --arg description "Index search tool for ${pattern}" \
    --arg pattern "${pattern}" \
    --arg custom "${custom_instructions}" \
    --arg pattern_key "${pattern_key}" \
    --arg custom_key "${custom_key}" \
    '{
      description: $description,
      configuration: {
        ($pattern_key): $pattern,
        ($custom_key): $custom
      }
    }')"

  if [[ "${include_type}" == "1" ]]; then
    payload="$(jq -cn --arg type "${tool_type}" --argjson payload "${payload}" '$payload + {type: $type}')"
  fi

  if [[ "${include_id}" == "1" ]]; then
    payload="$(jq -cn --arg id "${tool_id}" --argjson payload "${payload}" '$payload + {id: $id}')"
    printf '%s\n' "${payload}"
  else
    printf '%s\n' "${payload}"
  fi
}

upsert_tool_from_file() {
  local tool_file="$1"
  local tool_id
  local pattern
  local custom_instructions
  local payload
  local endpoint
  local method
  local attempt
  local include_id
  local include_type

  tool_id="$(extract_value "Tool ID" "${tool_file}")"
  pattern="$(extract_value "Target pattern" "${tool_file}")"
  custom_instructions="$(extract_custom_instructions "${tool_file}")"

  if [[ -z "${tool_id}" || -z "${pattern}" ]]; then
    echo "ERROR: Failed to parse tool definition from ${tool_file}"
    exit 1
  fi

  if tool_exists "${tool_id}"; then
    echo "Updating tool ${tool_id}."
    method="PUT"
    endpoint="${API_BASE}/tools/${tool_id}"
    include_id="0"
    include_type="0"
  else
    echo "Creating tool ${tool_id}."
    method="POST"
    endpoint="${API_BASE}/tools"
    include_id="1"
    include_type="1"
  fi

  local attempts=(
    "index pattern custom_instructions"
    "index_search pattern custom_instructions"
    "index index_pattern custom_instructions"
    "index_search index_pattern custom_instructions"
    "index pattern customInstructions"
    "index_search pattern customInstructions"
    "index index_pattern customInstructions"
    "index_search index_pattern customInstructions"
  )

  local idx=0
  local total="${#attempts[@]}"
  for attempt in "${attempts[@]}"; do
    idx=$((idx + 1))
    # shellcheck disable=SC2086
    set -- ${attempt}
    payload="$(build_payload "${tool_id}" "${pattern}" "${custom_instructions}" "$1" "$2" "$3" "${include_id}" "${include_type}")"
    if submit_tool_request "${method}" "${endpoint}" "${payload}" "$([[ ${idx} -eq ${total} ]] && echo 1 || echo 0)"; then
      return 0
    fi
  done

  echo "ERROR: Could not upsert tool ${tool_id} with any supported payload shape."
  return 1
}

upsert_tool_from_file "${REPO_ROOT}/tools/search_global_client_database"
upsert_tool_from_file "${REPO_ROOT}/tools/analyze_transaction_patterns"
upsert_tool_from_file "${REPO_ROOT}/tools/consult_compliance_handbook"
upsert_tool_from_file "${REPO_ROOT}/tools/scan_adverse_media"

echo "Tools initialization completed."
