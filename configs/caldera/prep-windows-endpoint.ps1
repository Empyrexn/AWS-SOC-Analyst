# Prep a Windows LAB endpoint so the Caldera Sandcat agent can deploy.
# Run as Administrator. LAB ONLY — the detection stack under test is Sysmon/Wazuh/SO,
# not Defender. See docs/08-caldera.md
#
# Defender's AMSI blocks the Sandcat one-liner ("ScriptContainedMaliciousContent").
# A folder exclusion does NOT help — the block is at the script-content level.

# Step 1 (GUI, must be first): Windows Security -> Virus & threat protection
#   -> Manage settings -> turn OFF Tamper Protection.
#   (Tamper Protection guards the setting below; it can't be disabled from PowerShell.)

# Step 2: disable real-time protection
Set-MpPreference -DisableRealtimeMonitoring $true

# Step 3: in the Caldera UI (login red) -> Agents -> Deploy an agent -> Sandcat,
#   set app.contact.http to  http://10.0.10.29:8888  (HOST IP, not localhost),
#   then run the PowerShell one-liner here as Administrator.
#   It drops C:\Users\Public\splunkd.exe and registers in group "red".
