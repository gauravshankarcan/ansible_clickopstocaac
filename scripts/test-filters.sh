#!/usr/bin/env bash
# Validate all extract filters complete successfully (smoke test)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CREDS_FILE="${CREDS_FILE:-${HOME}/.bashrc_eda_session}"

if [[ -f "${CREDS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CREDS_FILE}"
fi

export AAP_URL="${AAP_URL:-${AAP_BASE:-${SOURCE_AAP_URL:-}}}"
export SOURCE_AAP_URL="${SOURCE_AAP_URL:-${AAP_URL:-}}"

FILTERS=(
  all
  admin
  gateway
  controller
  eda
  job_templates
  workflow_job_templates
  inventories
  inventory_sources
  projects
  credentials
  credential_input_sources
  execution_environments
  schedules
  notifications
  settings
  organizations
  users
  teams
  roles
  labels
  instances
  instance_groups
  applications
  authenticators
  gateway_services
  eda_projects
  eda_rulebooks
  eda_credentials
  eda_event_streams
  eda_decision_environments
)

PASS=0
FAIL=0
FAILED_FILTERS=()

echo "==> Testing ${#FILTERS[@]} extract filters against ${AAP_URL:-${AAP_BASE:-unset}}"
echo ""

for filter in "${FILTERS[@]}"; do
  printf '%-30s ' "${filter}..."
  if "${REPO_ROOT}/scripts/extract.sh" --filter "${filter}" > "/tmp/caac_test_${filter}.log" 2>&1; then
    latest="$(ls -dt "${REPO_ROOT}"/output/caac_* 2>/dev/null | head -1 || true)"
    if [[ -n "${latest}" && -f "${latest}/apply.yml" && -d "${latest}/configs" ]]; then
      count="$(find "${latest}/configs" -maxdepth 1 -name '*.yml' ! -name connection.yml | wc -l)"
      echo "OK (${count} config files -> ${latest##*/})"
      PASS=$((PASS + 1))
    else
      echo "FAIL (missing apply.yml or configs/)"
      FAIL=$((FAIL + 1))
      FAILED_FILTERS+=("${filter}")
    fi
  else
    echo "FAIL (see /tmp/caac_test_${filter}.log)"
    FAIL=$((FAIL + 1))
    FAILED_FILTERS+=("${filter}")
  fi
done

echo ""
echo "==> Results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
  echo "Failed filters: ${FAILED_FILTERS[*]}"
  exit 1
fi
