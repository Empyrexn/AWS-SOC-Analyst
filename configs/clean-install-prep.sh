#!/usr/bin/env bash
# Security Onion clean-install prep (Oracle Linux 9).
# Installing cron BEFORE so-setup avoids the Salt master/minion + "No Top file matches"
# cascade that the minimal OS triggers. Run on a CLEAN instance.
# See docs/05-security-onion.md
set -euo pipefail

# 1) cron must exist before so-setup
sudo dnf install -y cronie
sudo systemctl enable --now crond

# 2) get the installer
sudo dnf install -y git
git clone -b 2.4/main https://github.com/Security-Onion-Solutions/securityonion
cd securityonion

# 3) run setup (interactive wizard)
#    EVAL ; mgmt = primary NIC (ens5) DHCP ; monitor = secondary sniff NIC (ens6, SPACEBAR
#    to select) ; short hostname ; Direct internet ; default Docker range ;
#    web access = mgmt IP ; allow 10.0.0.0/16
sudo bash so-setup-network

# After: sudo so-status   (expect healthy / GREEN grid)
# Add a web login: sudo so-user add you@example.com
