#!/usr/bin/env bash
# Apply config-as-code bundle to target AAP 2.5+ / 2.7+
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CREDS_FILE="${CREDS_FILE:-${HOME}/.bashrc_eda_session}"
APPLY_PHASES_FILE="${REPO_ROOT}/roles/caac_export/vars/apply_phases.yml"

BUNDLE_DIR=""
PHASE="all"
CHECK_MODE=""
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: apply.sh [OPTIONS]

Apply a generated output/caac_<timestamp> bundle to a target AAP instance.

Options:
  --bundle PATH       Path to caac output directory (default: latest in output/)
  --phase PHASE       Comma-separated apply phase(s) (default: all)
  --check             Run ansible-playbook in check mode (dry-run)
  --creds-file PATH   Credentials file to source (default: ~/.bashrc_eda_session)
  -e, --extra-vars V  Extra ansible-playbook -e argument (repeatable)
  -h, --help          Show this help

Phases:
  all
  gateway / admin     Gateway administrative objects
  organizations
  authenticators
  settings
  gateway_services
  credential_types
  credentials
  projects
  inventories
  job_templates
  workflow_job_templates
  schedules
  rbac
  users
  teams
  roles
  eda
  controller

Environment — target (apply):
  TARGET_AAP_URL / AAP_URL / AAP_BASE
  TARGET_AAP_USER / AAP_USER
  TARGET_AAP_PASS / AAP_PASS
  TARGET_AAP_TOKEN / AAP_TOKEN

Examples:
  ./scripts/apply.sh --bundle output/caac_20260101_120000 --check
  ./scripts/apply.sh --phase eda --check
  ./scripts/apply.sh --phase organizations,credentials,projects --check

EOF
}

normalize_phase() {
  local phase="$1"
  phase="$(echo "${phase}" | xargs | tr '[:upper:]' '[:lower:]')"
  case "${phase}" in
    admin|gateway_orgs) echo "gateway" ;;
    organizations) echo "organizations" ;;
    *) echo "${phase}" ;;
  esac
}

build_phase_roles_var() {
  local phases_csv="$1"
  python3 - "${APPLY_PHASES_FILE}" "${phases_csv}" <<'PY'
import sys
import yaml

phases_file, phases_csv = sys.argv[1], sys.argv[2]
with open(phases_file, encoding="utf-8") as fh:
    catalog = yaml.safe_load(fh)["apply_phase_roles"]

aliases = {"admin": "gateway", "gateway_orgs": "organizations"}
roles = []
seen = set()
for raw in phases_csv.split(","):
    phase = raw.strip().lower()
    phase = aliases.get(phase, phase)
    if phase in ("", "all"):
        continue
    if phase not in catalog:
        raise SystemExit(f"Unknown phase: {phase}")
    for role in catalog[phase]:
        key = role["role"]
        if key not in seen:
            roles.append(role)
            seen.add(key)

if roles:
    print(yaml.dump({"aap_configuration_dispatcher_roles": roles}, default_flow_style=False).strip())
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --check)
      CHECK_MODE="--check"
      shift
      ;;
    --creds-file)
      CREDS_FILE="$2"
      shift 2
      ;;
    -e|--extra-vars)
      EXTRA_ARGS+=("-e" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -f "${CREDS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CREDS_FILE}"
fi

export AAP_URL="${AAP_URL:-${AAP_BASE:-${TARGET_AAP_URL:-}}}"
export TARGET_AAP_URL="${TARGET_AAP_URL:-${AAP_URL:-}}"

if [[ -z "${BUNDLE_DIR}" ]]; then
  BUNDLE_DIR="$(ls -dt "${REPO_ROOT}"/output/caac_* 2>/dev/null | head -1 || true)"
fi

if [[ -z "${BUNDLE_DIR}" || ! -f "${BUNDLE_DIR}/apply.yml" ]]; then
  echo "No apply bundle found. Run extract.sh first or pass --bundle PATH." >&2
  exit 1
fi

PHASE_ROLES_FILE=""
if [[ "${PHASE}" != "all" ]]; then
  PHASE_ROLES_FILE="$(mktemp)"
  build_phase_roles_var "${PHASE}" > "${PHASE_ROLES_FILE}"
fi

cd "${BUNDLE_DIR}"

CMD=(ansible-playbook apply.yml)
export ANSIBLE_CONFIG=ansible.cfg
[[ -n "${CHECK_MODE}" ]] && CMD+=("${CHECK_MODE}")
[[ -n "${PHASE_ROLES_FILE}" ]] && CMD+=(-e "@${PHASE_ROLES_FILE}")
CMD+=("${EXTRA_ARGS[@]}")

echo "==> Applying bundle: ${BUNDLE_DIR}"
echo "    Target URL: ${TARGET_AAP_URL:-${AAP_URL:-${AAP_BASE:-unset}}}"
echo "    Phase: ${PHASE}"
[[ -n "${CHECK_MODE}" ]] && echo "    Mode: check (dry-run)"

"${CMD[@]}"
[[ -n "${PHASE_ROLES_FILE}" ]] && rm -f "${PHASE_ROLES_FILE}"
