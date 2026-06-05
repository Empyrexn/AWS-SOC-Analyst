# Attack Walkthroughs & Screenshots

End-to-end demonstrations that the lab detects real attacks. Each folder is one high-value attack, documented attacker → detection → triage → mitigation, mapped to MITRE ATT&CK, with the screenshots that prove it.

> **How to use:** run each attack against your own isolated lab targets, capture the screenshots called out in the walkthrough (filenames are pre-specified so they render automatically), and drop them into that attack's folder. Everything here is performed against **deliberately vulnerable training targets inside a private, security-group-gated VPC** — never against systems you don't own.

| # | Attack | MITRE ATT&CK | Primary detection |
|---|---|---|---|
| 01 | [Network recon — Nmap scan](./01-network-recon-nmap/) | T1046 / T1595 | Security Onion (Suricata) |
| 02 | [SSH brute force](./02-ssh-brute-force/) | T1110.001 | Wazuh → TheHive → Cortex |
| 03 | [Web SQL injection (DVWA)](./03-web-sql-injection-dvwa/) | T1190 / OWASP A03 | Wazuh (container logs) + Suricata |
| 04 | [vsftpd 2.3.4 backdoor RCE](./04-vsftpd-backdoor-rce/) | T1190 (CVE-2011-2523) | Security Onion + Wazuh |
| 05 | [Samba usermap_script RCE](./05-samba-usermap-rce/) | T1190 (CVE-2007-2447) | Security Onion + Wazuh |
| 06 | [AD password spray + Kerberoasting](./06-ad-password-spray-kerberoast/) | T1110.003 / T1558.003 | Windows events + Sysmon → Wazuh |
| 07 | [LSASS credential dumping](./07-credential-dumping-lsass/) | T1003.001 | Sysmon EID 10 → Wazuh |
| 08 | [Caldera adversary emulation](./08-caldera-adversary-emulation/) | T1071 + chain | Sysmon/Wazuh + Security Onion |

## The pipeline each one exercises

```
Attack (Kali / Caldera)  →  Host telemetry (Wazuh + Sysmon)  ┐
                         →  Network telemetry (Security Onion) ┼→ TheHive alert → Cortex enrichment → Mitigation
```

## Walkthrough structure (consistent across all eight)

1. **Scenario & ATT&CK mapping** — what it is and why it matters
2. **The attack** — exact steps from the attacker host
3. **Detection** — where it surfaces in each tool, with rule IDs / event IDs
4. **Triage** — what the analyst does with it
5. **Mitigation & remediation** — how to actually prevent/fix it
6. **Detection engineering** — rule ideas and tuning notes
7. **Screenshots checklist** — the exact shots to capture
