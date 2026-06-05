# 03 — Wazuh (SIEM/XDR)

Central host-based detection: a Wazuh manager + dashboard, with agents on every host (Linux + Windows), Sysmon telemetry on Windows, and Docker container-log collection on the vuln host. Wazuh is also the source of the automated alerts that feed TheHive (see [07](./07-wazuh-thehive-integration.md)).

This build's manager: **10.0.10.125** (SSH user `wazuh-user`; dashboard `admin` / the capitalized instance-ID).

---

## 1. Wazuh manager

### Launch
- AMI: **Wazuh All-in-One** (AWS Marketplace, by Wazuh Inc. — manager + indexer + dashboard in one)
- Type: `t3.large` (8 GB) minimum; `t3.xlarge` is comfier
- Subnet: `secops-subnet` (10.0.10.0/24), **no public IP**
- SG: `sg-secops`
- Key: `SOC-Analyst-Bastion-Key`

> Alternative (non-Marketplace): on Ubuntu/AL, `curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh && sudo bash ./wazuh-install.sh -a`.

### Access the dashboard
Tunnel through the bastion, then browse:
```bash
ssh -i SOC-Analyst-Bastion-Key.pem -L 8443:10.0.10.125:443 ec2-user@<bastion-public-ip>
# browse https://localhost:8443   (accept the self-signed cert)
```
Default dashboard login on the Marketplace AMI is **`admin`** with the **instance ID, first letter capitalized** as the password. Change it after first login.

---

## 2. Linux agents (Ubuntu vuln host, Kali)

Install from the Wazuh APT repo and bake the manager IP in via env vars at install time (this writes the `<server><address>` correctly):

```bash
# add repo + key (Wazuh docs), then:
sudo WAZUH_MANAGER="10.0.10.125" WAZUH_AGENT_NAME="vuln-docker-host" \
  apt-get install -y wazuh-agent
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
```

For Kali, same commands with `WAZUH_AGENT_NAME="kali"`.

Confirm on the manager dashboard (Agents) that the agent shows **Active**.

---

## 3. Docker container-log collection (vuln host only)

So Wazuh ingests the vulnerable apps' logs, add a `localfile` block **inside** `<ossec_config>` in `/var/ossec/etc/ossec.conf` on the vuln host:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/lib/docker/containers/*/*-json.log</location>
</localfile>
```

```bash
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent           # active (running)
```

Notes:
- The block **must** sit between `<ossec_config>` and `</ossec_config>`; outside it the agent won't start.
- The agent's logcollector runs as **root**, so it can read the root-only `/var/lib/docker/containers/` path — no permission change needed.
- The `*/*` wildcard auto-discovers every container's log, including ones started later. Logs only appear once containers are running and writing (`docker ps` + `sudo ls /var/lib/docker/containers/*/*-json.log`).

---

## 4. Windows agents (DC + clients)

Install the MSI with the manager baked in, then start the service:

```powershell
msiexec.exe /i wazuh-agent-4.14.0-1.msi /q `
  WAZUH_MANAGER="10.0.10.125" `
  WAZUH_AGENT_NAME="dc01" `
  WAZUH_REGISTRATION_SERVER="10.0.10.125"
NET START WazuhSvc
```

Repeat per host with a unique `WAZUH_AGENT_NAME` (`dc01`, `client01`, `client02`).

**Gotcha:** if the MSI is installed **without** `WAZUH_MANAGER`, the `<server><address>` in `C:\Program Files (x86)\ossec-agent\ossec.conf` stays the placeholder `10.0.10.x`. Hand-edit it to `10.0.10.125` and restart the service (`NET STOP WazuhSvc & NET START WazuhSvc`).

---

## 5. Sysmon on Windows endpoints

Sysmon gives rich process/network/registry telemetry. The default Windows `ossec.conf` **already** collects the Sysmon channel (`Microsoft-Windows-Sysmon/Operational` eventchannel) — no manual Wazuh edit needed. You only need to install Sysmon itself:

```powershell
# download Sysmon + SwiftOnSecurity config, then from the extracted folder:
.\Sysmon64.exe -accepteula -i sysmonconfig.xml
```
(The SwiftOnSecurity config file is commonly named `sysmonconfig-export.xml` — pass whatever you downloaded.)

Verify in Event Viewer: Applications and Services Logs → Microsoft → Windows → **Sysmon/Operational** is populating.

---

## Verification checklist

- [ ] Dashboard reachable via tunnel; default password changed.
- [ ] All agents (vuln host, Kali, DC, clients) show **Active** in Agents.
- [ ] Generate traffic (hit DVWA from Kali) → events appear under the vuln-host agent.
- [ ] Windows agents' `<server><address>` is `10.0.10.125` (not the placeholder).
- [ ] Sysmon events flow into Wazuh from the Windows hosts.
