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

extract_section_value() {
  local section_name="$1"
  local file="$2"
  awk -v section="${section_name}" '
    $0 ~ ("^" section ":") {
      while (getline) {
        if ($0 ~ /^-+$/) { continue }
        if ($0 ~ /^[[:space:]]*$/) { continue }
        print $0
        exit
      }
    }
  ' "${file}"
}

extract_custom_instructions() {
  local file="$1"
  awk '
    /^Custom Instructions:/ {capture=1; next}
    capture {
      if ($0 ~ /^-+$/) { next }
      lines[++n]=$0
    }
    END {
      start=1
      while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++
      finish=n
      while (finish >= start && lines[finish] ~ /^[[:space:]]*$/) finish--
      for (i=start; i<=finish; i++) print lines[i]
    }
  ' "${file}"
}

agent_exists() {
  local agent_id="$1"
  local status
  status="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "${auth_header}" \
    "${API_BASE}/agents/${agent_id}")"
  [[ "${status}" == "200" ]]
}

submit_agent_request() {
  local method="$1"
  local endpoint="$2"
  local payload="$3"
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

  echo "API ${method} ${endpoint} failed with status ${status}" >&2
  cat "${response_file}" >&2
  rm -f "${response_file}"
  return 1
}

build_agent_payload() {
  local agent_id="$1"
  local display_name="$2"
  local display_description="$3"
  local instructions="$4"
  local tool_ids_json="$5"
  local include_id="$6"

  local payload
  payload="$(jq -cn \
    --arg name "${display_name}" \
    --arg description "${display_description}" \
    --arg instructions "${instructions}" \
    --argjson tool_ids "${tool_ids_json}" \
    '{
      name: $name,
      description: $description,
      configuration: {
        instructions: $instructions,
        tools: [
          {
            tool_ids: $tool_ids
          }
        ]
      }
    }')"

  if [[ "${include_id}" == "1" ]]; then
    jq -cn --arg id "${agent_id}" --argjson payload "${payload}" '$payload + {id: $id}'
  else
    printf '%s\n' "${payload}"
  fi
}

tool_ids_for_agent() {
  local agent_id="$1"
  case "${agent_id}" in
    financial-crime-agent)
      jq -cn '[
        "search_global_client_database",
        "analyze_transaction_patterns",
        "consult_compliance_handbook",
        "scan_adverse_media"
      ]'
      ;;
    identity_agent)
      jq -cn '[
        "search_global_client_database"
      ]'
      ;;
    *)
      echo "ERROR: Unknown agent id ${agent_id} for tool binding."
      exit 1
      ;;
  esac
}

upsert_agent_from_file() {
  local prompt_file="$1"
  local agent_id
  local display_name
  local display_description
  local instructions
  local tool_ids
  local payload
  local endpoint
  local method
  local include_id

  agent_id="$(extract_section_value "Agent ID" "${prompt_file}")"
  display_name="$(extract_section_value "Display name" "${prompt_file}")"
  display_description="$(extract_section_value "Display description" "${prompt_file}")"
  instructions="$(extract_custom_instructions "${prompt_file}")"

  if [[ -z "${agent_id}" || -z "${display_name}" || -z "${instructions}" ]]; then
    echo "ERROR: Failed to parse agent definition from ${prompt_file}"
    exit 1
  fi

  tool_ids="$(tool_ids_for_agent "${agent_id}")"

  if agent_exists "${agent_id}"; then
    echo "Updating agent ${agent_id}."
    method="PUT"
    endpoint="${API_BASE}/agents/${agent_id}"
    include_id="0"
  else
    echo "Creating agent ${agent_id}."
    method="POST"
    endpoint="${API_BASE}/agents"
    include_id="1"
  fi

  payload="$(build_agent_payload "${agent_id}" "${display_name}" "${display_description}" "${instructions}" "${tool_ids}" "${include_id}")"
  submit_agent_request "${method}" "${endpoint}" "${payload}"
}

upsert_agent_from_file "${REPO_ROOT}/prompts/financial-crime-agent"
upsert_agent_from_file "${REPO_ROOT}/prompts/identity_agent"

echo "Agents initialization completed."
