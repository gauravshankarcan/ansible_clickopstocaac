#!/usr/bin/env bash
# Install Ansible collections required for clickopstocaac extract/apply
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "==> Installing Galaxy collections from requirements.yml"
ansible-galaxy collection install -r requirements.yml

echo "==> Installing ansible.platform from GitHub (gateway API plugin)"
ansible-galaxy collection install --force --no-deps git+https://github.com/ansible/ansible.platform.git

echo "==> Installing infra.aap_configuration_extended devel from GitHub"
ansible-galaxy collection install --force --no-deps git+https://github.com/redhat-cop/aap_configuration_extended.git,devel

echo "==> Installing ansible.controller (required for controller object apply)"
ansible-galaxy collection install ansible.controller || true

echo "==> Installing ansible.eda (required for EDA object apply)"
ansible-galaxy collection install ansible.eda || true

echo ""
echo "==> Done."
echo "    For apply on AAP 2.7+, install from Automation Hub when available:"
echo "      ansible.controller, ansible.eda (validated versions matching your AAP release)"
