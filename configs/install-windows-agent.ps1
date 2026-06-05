# Install the Wazuh agent (MSI) + Sysmon on a Windows endpoint. Run as Administrator.
# See docs/03-wazuh.md
# GOTCHA: if you install the MSI WITHOUT WAZUH_MANAGER, <server><address> stays the
# placeholder 10.0.10.x in C:\Program Files (x86)\ossec-agent\ossec.conf — hand-edit it
# to the manager IP and restart the service.

$ManagerIP = "10.0.10.125"          # <-- your Wazuh manager
$AgentName = $env:COMPUTERNAME       # or set explicitly: "dc01" / "client01"
$Msi       = "wazuh-agent-4.14.0-1.msi"   # <-- the MSI you downloaded

# --- Wazuh agent ---
msiexec.exe /i $Msi /q `
  WAZUH_MANAGER="$ManagerIP" `
  WAZUH_AGENT_NAME="$AgentName" `
  WAZUH_REGISTRATION_SERVER="$ManagerIP"
NET START WazuhSvc

# --- Sysmon (SwiftOnSecurity config) ---
# Sysmon collection is ALREADY in the default Windows ossec.conf
# (Microsoft-Windows-Sysmon/Operational eventchannel) — no Wazuh edit needed.
# Download Sysmon + the SwiftOnSecurity config first, then from that folder:
.\Sysmon64.exe -accepteula -i sysmonconfig-export.xml
