#!/usr/bin/env bash
# Extract AAP/AWX objects to config-as-code (output/caac_<timestamp>/)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CREDS_FILE="${CREDS_FILE:-${HOME}/.bashrc_eda_session}"

FILTER="all"
ORG=""
VALIDATE_CERTS=""
SOURCE_PLATFORM=""
TARGET_PLATFORM="aap27"
MIGRATION_MODE="false"
DEFAULT_EE=""
EXTRA_VARS=()

usage() {
  cat <<'EOF'
Usage: extract.sh [OPTIONS]

Extract automation objects from AWX/AAP into config-as-code output.

Options:
  --filter FILTER           Comma-separated filter(s) (default: all)
  --source-platform PLAT    awx20 | awx24 | aap24 | aap25 | aap26 | aap27 | auto
  --target-platform PLAT    Target for apply bundle metadata (default: aap27)
  --migration-mode          Enable cross-version transforms (org/credential maps, field strip)
  --org NAME                Export only objects for this organization
  --org-map JSON            Map org names for target, e.g. '{"Old":"New"}'
  --default-ee NAME         Default execution environment for job templates missing EE
  --validate-certs BOOL     Set SOURCE_AAP_VALIDATE_CERTS / AAP_VALIDATE_CERTS
  --creds-file PATH         Credentials file to source (default: ~/.bashrc_eda_session)
  -e, --extra-vars V        Extra ansible-playbook -e argument (repeatable)
  -h, --help                Show this help

Environment — source (extract):
  SOURCE_AAP_URL / AAP_URL / AAP_BASE
  SOURCE_AAP_USER / AAP_USER
  SOURCE_AAP_PASS / AAP_PASS
  SOURCE_AAP_TOKEN / AAP_TOKEN
  CAAC_SOURCE_PLATFORM      Same as --source-platform

Environment — target (embedded in apply bundle metadata):
  CAAC_TARGET_PLATFORM      Same as --target-platform

Migration examples:
  # AWX 20.x controller-only export for AAP 2.7 import
  ./scripts/extract.sh --source-platform awx20 --filter controller --migration-mode

  # AAP 2.5+ full export
  ./scripts/extract.sh --source-platform aap25 --filter all

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      FILTER="$2"
      shift 2
      ;;
    --source-platform)
      SOURCE_PLATFORM="$2"
      shift 2
      ;;
    --target-platform)
      TARGET_PLATFORM="$2"
      shift 2
      ;;
    --migration-mode)
      MIGRATION_MODE="true"
      shift
      ;;
    --org)
      ORG="$2"
      shift 2
      ;;
    --org-map)
      EXTRA_VARS+=("-e" "caac_migration_org_map=${2}")
      MIGRATION_MODE="true"
      shift 2
      ;;
    --default-ee)
      DEFAULT_EE="$2"
      shift 2
      ;;
    --validate-certs)
      VALIDATE_CERTS="$2"
      shift 2
      ;;
    --creds-file)
      CREDS_FILE="$2"
      shift 2
      ;;
    -e|--extra-vars)
      EXTRA_VARS+=("-e" "$2")
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

# Normalize URL aliases (customer creds often set AAP_BASE only)
export AAP_URL="${AAP_URL:-${AAP_BASE:-${SOURCE_AAP_URL:-}}}"
export SOURCE_AAP_URL="${SOURCE_AAP_URL:-${AAP_URL:-}}"

cd "${REPO_ROOT}"

PLAYBOOK_VARS=(-e "extract_filter=${FILTER}")
PLAYBOOK_VARS+=(-e "caac_target_platform=${TARGET_PLATFORM}")
PLAYBOOK_VARS+=(-e "caac_migration_mode=${MIGRATION_MODE}")

if [[ "${MIGRATION_MODE}" == "true" ]]; then
  PLAYBOOK_VARS+=(-e "caac_migration_format_for_gateway=true")
fi

if [[ -n "${SOURCE_PLATFORM}" ]]; then
  PLAYBOOK_VARS+=(-e "caac_source_platform=${SOURCE_PLATFORM}")
fi

if [[ -n "${DEFAULT_EE}" ]]; then
  PLAYBOOK_VARS+=(-e "caac_migration_default_ee=${DEFAULT_EE}")
fi

if [[ -n "${ORG}" ]]; then
  PLAYBOOK_VARS+=(-e "organization_filter=${ORG}")
fi

if [[ -n "${VALIDATE_CERTS}" ]]; then
  export SOURCE_AAP_VALIDATE_CERTS="${VALIDATE_CERTS}"
  export AAP_VALIDATE_CERTS="${VALIDATE_CERTS}"
fi

echo "==> Extracting config-as-code (filter: ${FILTER}, migration: ${MIGRATION_MODE})"
ansible-playbook playbooks/extract.yml --skip-tags yaml_format "${PLAYBOOK_VARS[@]}" "${EXTRA_VARS[@]}"

LATEST="$(ls -dt "${REPO_ROOT}"/output/caac_* 2>/dev/null | head -1 || true)"
if [[ -n "${LATEST}" ]]; then
  echo ""
  echo "==> Output: ${LATEST}"
  echo "    Apply:  cd ${LATEST} && ${REPO_ROOT}/scripts/apply.sh --check"
  echo "    Phased: ${REPO_ROOT}/scripts/apply.sh --phase projects,job_templates --check"
fi
