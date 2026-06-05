# Build Documentation

Per-component build guides for the [SOC Analyst Home Lab on AWS](../README.md). Follow them in order — each assumes the previous ones are done. Together they let you rebuild the entire lab from scratch, with the real-world gotchas called out inline so you don't re-hit them.

| # | Guide | What it builds |
|---|---|---|
| 01 | [Network Foundation & Access](./01-network-foundation.md) | VPC, subnets, IGW/NAT, route tables, security groups, key pair, bastion, tunneling |
| 02 | [Vulnerable Targets & Kali](./02-vulnerable-targets-and-kali.md) | DVWA, Juice Shop, WebGoat, Metasploitable2 (Docker) + Kali attacker |
| 03 | [Wazuh](./03-wazuh.md) | Manager/dashboard, Linux + Windows agents, Sysmon, Docker log collection |
| 04 | [Active Directory](./04-active-directory.md) | `soc.lab` forest, DC, domain-joined Windows clients |
| 05 | [Security Onion](./05-security-onion.md) | Suricata/Zeek/PCAP + VPC Traffic Mirroring (VXLAN) |
| 06 | [TheHive + Cortex](./06-thehive-cortex.md) | Case management + analyzer enrichment (StrangeBee Docker stacks) |
| 07 | [Wazuh → TheHive Integration](./07-wazuh-thehive-integration.md) | Auto-alerting from Wazuh into TheHive (thehive4py v2) |
| 08 | [Caldera](./08-caldera.md) | Adversary emulation with Sandcat agents |
| 09 | [Nessus](./09-nessus.md) | Credentialed vulnerability scanning |

## Conventions used throughout

- **IPs** are this build's private addresses (`10.0.x.x`) — substitute your own. They're safe to publish (RFC 1918, internal-only).
- **Secrets** (API keys, passwords, the bastion's public IP) are intentionally **not** committed. Rotate anything that was ever pasted in plaintext during the build.
- All access to private hosts is **through the bastion** via SSH tunnels / SOCKS — see [01](./01-network-foundation.md#7-tunneling-reference-how-you-reach-everything-private).
- Each guide ends with a **verification checklist** so you can confirm the component before moving on.
