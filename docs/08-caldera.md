# 08 — Caldera (Adversary Emulation)

MITRE Caldera runs scripted, repeatable ATT&CK-based adversary emulation against the lab endpoints — the controlled "attacker" that exercises the whole detection pipeline (Wazuh/Sysmon on the host, Security Onion on the network).

This build: Caldera on **10.0.10.29** (same host as TheHive/Cortex), serving on **:8888**. Default creds `red/admin` (red team) and `blue/admin`.

---

## 1. Deploy Caldera

On the secops Docker host:
```bash
git clone https://github.com/mitre/caldera.git --recursive ~/caldera
cd ~/caldera
docker compose up -d
```
Caldera serves its web UI on port **8888**. Reach it via a bastion tunnel:
```bash
ssh -i SOC-Analyst-Bastion-Key.pem -L 8888:10.0.10.29:8888 ec2-user@<bastion-public-ip>
# browse http://localhost:8888  (login red / admin)
```
(The lab runs Caldera with `--insecure` / default lab settings — fine for an isolated lab, never for anything exposed.)

---

## 2. Deploy Sandcat agents to endpoints

In the Caldera UI (logged in as **red**) → **Agents → Deploy an agent → Sandcat**. **Set `app.contact.http` to `http://10.0.10.29:8888`** (the host IP — **not** `localhost`, or agents on other machines can't call back). Copy the deployment one-liner.

### Windows endpoints — the Defender/AMSI gotcha
The Sandcat PowerShell one-liner is blocked by Windows Defender's **AMSI** script scanning (`ScriptContainedMaliciousContent`). **A folder exclusion does NOT help** — the block is at the script-content level, not file scanning.

Fix on each lab client (lab-only; the detection stack under test is Sysmon/Wazuh/SO, not Defender):
1. **Disable Tamper Protection** via GUI: Windows Security → Virus & threat protection → **Manage settings** → Tamper Protection Off. (Must be done in the GUI first — it guards the setting below.)
2. Then disable real-time protection:
   ```powershell
   Set-MpPreference -DisableRealtimeMonitoring $true
   ```
Now run the Sandcat one-liner **as Administrator**. It drops `C:\Users\Public\splunkd.exe` and registers the agent in group `red`. Sysmon still logs the agent's process/network behavior — which is the point.

### Linux endpoint
The vuln host uses Caldera's **bash** one-liner (no AMSI issue) — run it as shown in the UI.

---

## 3. Run an operation

Caldera UI → **Operations → Create Operation** → pick an **adversary profile** (a chain of ATT&CK techniques) → select the agent group (`red`) → **Start**. Watch the abilities execute on the endpoints.

Then pivot to detection: the same activity should surface as **Wazuh/Sysmon** alerts (host) and in **Security Onion Hunt** (network), and — if it trips a level≥7 rule — auto-create a **TheHive** alert ([07](./07-wazuh-thehive-integration.md)). That round trip is the full SOC loop.

---

## Verification checklist

- [ ] Caldera UI reachable via tunnel; login works.
- [ ] Sandcat agents check in (Agents page shows them) with `app.contact.http` = host IP.
- [ ] Windows agent deployed after disabling Tamper + real-time protection.
- [ ] An operation runs to completion and its techniques appear in Wazuh and Security Onion.
