# 01 — Network Reconnaissance (Nmap)

**MITRE ATT&CK:** T1595 Active Scanning · T1046 Network Service Discovery
**Attacker:** Kali (`attack-subnet`) · **Target:** vuln host `10.0.40.222` · **Primary detection:** Security Onion (Suricata)

Recon is the first move in almost every intrusion. Catching a scan early — and being able to show the analyst's view of it — is foundational SOC work.

---

## 1. The attack

From Kali, a service/version + default-script scan of the target:
```bash
nmap -sV -sC -p- 10.0.40.222
```
This enumerates open ports and service versions across all 65535 ports — loud and obvious by design.

![Nmap scan output](./01-nmap-output.png)
> 📸 *Capture: the Kali terminal showing the full `nmap -sV` results — open ports (21/22/80/445/3306/...), service banners, and versions.*

---

## 2. Detection

**Security Onion (Suricata + Zeek)** is the star here — a port sweep is a network-layer event.
- In the SO UI → **Alerts**, filter for the Kali source IP (`10.0.20.x`). Expect Suricata ET signatures for port scans / NMAP scripting engine activity.
- In **Hunt**, the scan shows as a burst of connections from one source to many destination ports in a short window — Zeek `conn.log` is ideal for visualizing this fan-out.

![Security Onion scan alert](./02-securityonion-scan-alert.png)
> 📸 *Capture: the SO Alerts view filtered to the Kali IP, showing the scan/recon Suricata alerts.*

![Zeek conn fan-out in Hunt](./03-securityonion-hunt-connfanout.png)
> 📸 *Capture: SO Hunt showing the one-source-to-many-ports connection pattern.*

**Wazuh** may also log connection attempts on the target depending on services hit, but the network layer (SO) is the authoritative detection for scanning.

---

## 3. Triage

The analyst's questions: *who* (source IP — internal pivot or external?), *what* (full sweep vs targeted ports?), *when* (one-off vs recurring?). A single internal host sweeping the whole subnet is a strong "compromised host doing discovery" signal. Note the source IP as an observable to pivot on.

---

## 4. Mitigation & remediation

- **Network segmentation** — security groups / NACLs limiting which hosts can reach which ports (the lab already restricts inbound; tighten east-west rules to mirror production).
- **Rate-limiting / IPS mode** — Suricata can drop, not just alert, on scan signatures when run inline.
- **Reduce attack surface** — close unused ports/services on the target (most Metasploitable services have no business being open).
- **Honeypot/canary ports** to make scanning trip high-confidence alerts.

---

## 5. Detection engineering

- Tune Suricata scan thresholds to your environment so legitimate vuln scans (your Nessus box) don't drown real recon — allowlist the Nessus source IP.
- A simple Sigma/Wazuh correlation: *N+ distinct destination ports from one source within M seconds* → alert. Great custom-rule exercise.

---

## Screenshots checklist
- [ ] `01-nmap-output.png` — Nmap results in Kali
- [ ] `02-securityonion-scan-alert.png` — SO Suricata scan alert
- [ ] `03-securityonion-hunt-connfanout.png` — Zeek connection fan-out in Hunt
