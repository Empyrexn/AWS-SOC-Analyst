# 06 - Active Directory: Password Spray + Kerberoasting

**MITRE ATT&CK:** T1110.003 Password Spraying - T1558.003 Kerberoasting
**Status:** VALIDATED - spray caught by stock Wazuh rules; kerberoasting gap closed with a **custom Wazuh rule**
**Attacker:** Kali `10.0.20.23` - **Target:** DC `soc.lab` / `dc01` (`10.0.30.83`)
**Detection:** Wazuh (Windows Security events via the DC agent)

This walkthrough **flips the sensor story.** Attacks 01/03/04/05 hit agentless containers, so detection lived at the network layer (Security Onion) and Wazuh was blind. Here the target is the Windows **AD domain**, where the DC runs a Wazuh agent - so **Wazuh is the primary detector.** The spray is caught by stock rules; kerberoasting needed a custom rule (the host-side twin of the Samba Suricata gap from [WT05](../05-samba-usermap-rce/)).

---

## 1. Setup

Created 6 standard domain users plus one service account with an SPN (`svc_sql`, `MSSQLSvc/web01.soc.lab:1433`) - the users give the spray multiple targets, the service account gives the roast a victim. One user (`bwilson`) deliberately uses the password we spray, so the spray finds a real credential and chains into the roast.

---

## 2. Part A - Password Spray (T1110.003)

One password across every account, from Kali:

```bash
nxc smb 10.0.30.83 -u users.txt -p 'Summer2026!' --continue-on-success
```

6 `STATUS_LOGON_FAILURE` + one hit (`[+] bwilson`):

![Password spray - one hit, many failures](https://github.com/user-attachments/assets/5389e507-9035-4a5a-9a28-af8b2cab42a7)


**Detection - Wazuh (dc01):**
- **`60122` "Logon Failure - Unknown user or bad password"** across *multiple distinct accounts* - that's the spray fingerprint (one password, many users), which is what distinguishes a spray from a single-account brute force.
- **`92652` "Successful Remote Logon Detected - bwilson - NTLM authentication, possible pass-the-hash"** - the *successful* hit flagged as suspicious (nxc authenticates over NTLM, tripping the PtH-flavored rule).

![Wazuh - spray detection (60122 / 92652)](https://github.com/user-attachments/assets/db3d6681-0593-44f9-9dc8-e217a5539a75)

![Wazuh DC dashboard - 6 authentication failures](https://github.com/user-attachments/assets/93868831-1163-41e4-b079-6ed50187e20d)

---

## 3. Part B - Kerberoasting (T1558.003)

Using the credential the spray found, request the SPN service ticket:

```bash
impacket-GetUserSPNs soc.lab/bwilson:'Summer2026!' -dc-ip 10.0.30.83 -request
```

**Obstacle (worth noting):** the first attempt failed with `KDC_ERR_ETYPE_NOSUPP` - Server 2022 creates accounts with **AES-only** keys, but impacket requests RC4. Enabling RC4 on `svc_sql` (realistic - attackers specifically hunt RC4-enabled service accounts) produced the roastable hash:

![Kerberoast - RC4 TGS hash extracted](https://github.com/user-attachments/assets/e47ddd3e-eaf6-4950-a37a-3b0a3e96b0fd)

```
$krb5tgs$23$*svc_sql$SOC.LAB$...   (23 = RC4, crackable offline with hashcat -m 13100)
```

**The detection gap - and the custom rule that closes it.** Out of the box, Wazuh raised **no alert** on the roast. Event **4769** (Kerberos service ticket) is one of the noisiest events in all of AD - every ticket for every user generates one - so SIEMs don't alert on it by default, and kerberoasting is invisible. So I authored a custom Wazuh rule that fires *only* when a 4769 uses **RC4 (0x17)** for a **non-machine** account - the kerberoasting tell:

```xml
<rule id="100100" level="12">
  <if_group>windows</if_group>
  <field name="win.system.eventID">^4769$</field>
  <field name="win.eventdata.ticketEncryptionType">^0x17$</field>
  <field name="win.eventdata.serviceName" negate="yes">\$$</field>
  <description>Possible Kerberoasting: RC4 (0x17) Kerberos service ticket (4769) requested for $(win.eventdata.serviceName).</description>
  <mitre><id>T1558.003</id></mitre>
</rule>
```

After deploying it on the manager, the re-run fired the rule at **level 12**:

![Custom rule 100100 fires - kerberoasting detected](https://github.com/user-attachments/assets/acf0ec04-97d5-46d1-ac3c-5c0af1b5b575)

```
Possible Kerberoasting: RC4 (0x17) Kerberos service ticket (4769) requested for svc_sql.   rule 100100, level 12
```

**Gap closed.** Full rule: [`configs/wazuh/local_rules.xml`](../../configs/wazuh/local_rules.xml). This is the **host-side counterpart** to the custom Suricata rule from WT05 - detection engineering across *both* network (Suricata) and host (Wazuh) sensors.

---

## 4. Triage

The spray surfaced a valid credential (`bwilson`) out of many failures; the roast yielded the `svc_sql` ticket hash, which cracks offline to recover the service-account password. That chain - **spray -> valid creds -> kerberoast -> offline crack -> service account** - is a classic AD escalation path. Source `10.0.20.23` (internal). With both detections live, an analyst sees the spray (60122 across accounts + 92652 on the hit) and the roast (custom 100100) as a connected story.

---

## 5. Mitigation & remediation

- **Long, random service-account passwords** (25+ chars) - makes offline cracking infeasible even with the hash.
- **Group Managed Service Accounts (gMSA)** - 120-char auto-rotated passwords; effectively unroastable.
- **Disable RC4 domain-wide** (AES only) - removes the downgrade tell and slows cracking. (`svc_sql` had to have RC4 re-enabled just to demo the classic attack.)
- **Account lockout / spray-aware thresholds** and **MFA** where feasible.
