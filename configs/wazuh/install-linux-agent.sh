#!/usr/bin/env bash
# Install the Wazuh agent on a Linux host (Ubuntu/Debian shown).
# Baking WAZUH_MANAGER in at install time writes <server><address> correctly.
# See docs/03-wazuh.md
set -euo pipefail

WAZUH_MANAGER_IP="10.0.10.125"     # <-- your Wazuh manager
AGENT_NAME="${1:-$(hostname)}"     # pass a name as arg 1, else hostname

# Add the Wazuh APT repo + GPG key (per current Wazuh docs), then:
sudo WAZUH_MANAGER="${WAZUH_MANAGER_IP}" WAZUH_AGENT_NAME="${AGENT_NAME}" \
  apt-get install -y wazuh-agent

sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
sudo systemctl status wazuh-agent --no-pager
