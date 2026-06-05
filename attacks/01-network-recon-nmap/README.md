# 01 - Network Reconnaissance (Nmap)

**MITRE ATT&CK:** T1046 Network Service Discovery (also T1595 Active Scanning, pre-compromise)
**Status:** VALIDATED - run end-to-end, detection confirmed
**Attacker:** Kali `10.0.20.23` (attack-subnet) - **Target:** vuln host `10.0.40.222` (vuln-subnet)
**Primary detection:** Security Onion / Suricata - **Host detection (Wazuh):** none, by design (see below)

Reconnaissance is the first move in almost every intrusion. This run shows the lab catching it cleanly at the network layer - and, just as importantly, shows *why the host layer stays silent*, which is the point of running both.

---

## 1. The attack

A service/version + default-script scan from Kali:
```bash
sudo nmap -sV -sC 10.0.40.222
```

Nmap enumerated the full Metasploitable service stack: FTP (vsftpd 2.3.4), OpenSSH, telnet, SMTP, HTTP (Apache 2.2.8), Samba (139/445), MySQL, PostgreSQL, UnrealIRCd (6667), DVWA (8081), Tomcat (8180), and a root bind shell on 1524.

![Nmap scan output](https://github.com/user-attachments/assets/d6fbe86c-8014-45d2-8323-08fd1c7696ae)

**Analyst note - target is containerized.** The scan leaked two tells that `10.0.40.222` is a Docker container, not a bare host: the FTP banner reported `PASV IP 172.17.0.2` (Docker's default bridge network) and the SMB hostname came back as `b50055b5120a` (a container ID). Useful context for scoping.

---

## 2. Detection - Security Onion (Suricata)

The scan generated **hundreds of Suricata alerts** from `10.0.20.23 -> 10.0.40.222`. Filtered in **Alerts** to the Kali source IP:

![Security Onion alerts](https://github.com/user-attachments/assets/62c068fe-28b0-4ae9-8a2d-c213b853af91)

Representative signatures that fired (real SIDs from this run):

| Signature | SID | Severity | Category | Triggered on |
|---|---|---|---|---|
| ET SCAN Nmap Scripting Engine User-Agent Detected | 2009358 | **high** | Web Application Attack | 80, 8081, 8083, 8180 |
| ET SCAN Possible Nmap User-Agent Observed | 2024364 | **high** | Web Application Attack | web ports |
| ET SCAN Potential SSH Scan | 2001219 | medium | Attempted Information Leak | 22 |
| ET SCAN Potential SSH Scan OUTBOUND | 2003068 | medium | Attempted Information Leak | 22 |
| ET SCAN Suspicious inbound to mySQL port 3306 | 2010937 | medium | Potentially Bad Traffic | 3306 |
| ET SCAN Suspicious inbound to PostgreSQL port 5432 | 2010939 | medium | Potentially Bad Traffic | 5432 |
| GPL NETBIOS SMB-DS IPC$ share access | 2102465 | low | Generic Protocol Command Decode | 445 |
| ET INFO NTLM Session Setup Request (Negotiate/Auth) | 2067085 / 2067087 | low | Misc activity | 445 |
| ET INFO NTLMv1 Session Setup Response - Challenge | 2067086 | low | Misc activity | 445 |
| ET CHAT IRC USER / NICK command | 2002023 / 2002024 | low | Misc activity | 6667 |
| ET CHAT IRC authorization message | 2000355 | low | Misc activity | 6667 |

**Why the highest-severity hits are the "Nmap User-Agent" rules:** the `-sC` default scripts (NSE) announce themselves with an identifiable Nmap User-Agent string on every HTTP probe, so Suricata flags each one `high`. That's a detection-vs-evasion lesson in one line: this scan was trivially attributable to Nmap *because* of `-sC`. A quieter scan (`-sS` with no scripts) would trip far fewer, lower-severity alerts - worth demonstrating as a follow-up.

**The scripts didn't just scan - they interacted.** NSE authenticated to SMB as guest (the NTLM session-setup alerts), connected to UnrealIRCd and sent NICK/USER (the IRC alerts), and probed MySQL/PostgreSQL. So a "recon" action produced real protocol-level telemetry across multiple services.

### Connection fan-out (Hunt)

Grouping **Hunt** by `destination.port` shows the classic one-source-to-many-ports pattern - the Metasploitable services light up: 8083, 8081, 80, 8180, 1524, 445, 21, 3306, 5432, 22, 25, 2222, 137, 135.

![Hunt destination.port fan-out](https://github.com/user-attachments/assets/e5a3436f-d648-47ea-969c-653c25aaaf83)

> Two analyst notes on this view: (1) `destination.port 4789` with the huge count is the **VXLAN traffic-mirror transport itself** (AWS encapsulation), not a scanned service - it's infrastructure. (2) This view wasn't source-filtered, so normal infra ports (53 DNS, 123 NTP, 389 LDAP) also appear; filter `source.ip = 10.0.20.23` to isolate the scan cleanly.

---

## 3. Why Wazuh saw nothing (and why that's correct)

Nothing meaningful appeared in **Wazuh** for this attack - and that is the expected, correct outcome:

- Wazuh is **host-based**: it analyzes *logs* from agents. A version scan connects, reads a banner, and disconnects without authenticating, so it generates little or no host log activity to alert on.
- The scanned services live **inside the Metasploitable container**, which runs no agent - only the Docker host does.

Reconnaissance is a **network-layer** event, so it is Security Onion's job, not Wazuh's. The contrast - network sensor loud, host sensor quiet - is the practical case for deploying both. Sensor placement matters.

---

## 4. Triage

One internal host (`10.0.20.23`) sweeping another host's full service range in seconds is a high-confidence "host doing discovery" signal - in a real environment, likely a compromised internal box performing internal recon. Key facts to record: source IP, target, time window, and the breadth of ports touched. Note the source IP as an observable.

---

## 5. Mitigation & remediation

- **Network segmentation** - security groups / NACLs limiting which hosts can reach which service ports east-west (the lab restricts inbound; tighten internal rules to mirror production).
- **Reduce attack surface** - close the unused/legacy services on the target (most Metasploitable ports have no business being open).
- **IPS mode** - Suricata can *drop* on these scan signatures when deployed inline, not just alert.
- **Allowlist sanctioned scanners** - exempt your Nessus host so authorized vuln scans don't bury real recon in noise.

---

## 6. Detection engineering

- The **Nmap NSE User-Agent** signature is a cheap, high-confidence IOC - keep it high-priority but allowlist the Nessus source IP.
- Build a correlation/threshold rule: *N+ distinct destination ports from one source within M seconds* -> "host port scan" (portable as a Sigma rule across SIEMs).
- Follow-up experiment to document: re-run as `sudo nmap -sS 10.0.40.222` (no scripts) and compare the alert volume/severity - demonstrates how scan technique changes detectability.
