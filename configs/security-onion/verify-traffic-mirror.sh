#!/usr/bin/env bash
# Verify VPC Traffic Mirroring is reaching Security Onion's sniff interface.
# Use the Linux interface name (ens6), NOT the eni-... ID.
# See docs/05-security-onion.md
set -euo pipefail

SNIFF_IF="ens6"   # secondary NIC = SO-Sniff-NI (mirror target)

echo "[*] Watching for VXLAN (UDP 4789) on ${SNIFF_IF}. Generate traffic from a source host..."
sudo tcpdump -ni "${SNIFF_IF}" udp port 4789

# Suricata/Zeek auto-decode standard VXLAN here, so no manual decap is normally needed.
# Fallback ONLY if a tool doesn't auto-decode — create a decap interface:
#   ip link add vxlan0 type vxlan id <VNI> dev ens6 dstport 4789
#   ip link set vxlan0 up
