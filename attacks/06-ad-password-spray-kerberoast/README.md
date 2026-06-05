# 06 — AD Password Spray + Kerberoasting

**MITRE ATT&CK:** T1110.003 Password Spraying · T1558.003 Kerberoasting
**Attacker:** Kali · **Target:** `soc.lab` (DC `10.0.30.83`) · **Detection:** Windows Security events + Sysmon → Wazuh

Active Directory is where most enterprise attacks actually play out. These two techniques are interview staples and produce distinctive, detectable Kerberos/logon telemetry.

---

## 1. The attack

**Password spray** — one common password against many users (stays under per-account lockout):
```bash
# using a CrackMapExec / NetExec style tool against the domain
nxc smb 10.0.30.83 -u users.txt -p 'Spring2025!' --continue-on-success
```

**Kerberoasting** — request service tickets for accounts with SPNs, then crack offline:
```bash
# request TGS tickets for SPN accounts (Impacket)
GetUserSPNs.py soc.lab/lowprivuser:Password123 -dc-ip 10.0.30.83 -request
```

![Spray + kerberoast](./01-spray-kerberoast.png)
> 📸 *Capture: the spray hit(s) and/or the GetUserSPNs output showing a retrieved TGS hash.*

---

## 2. Detection

**Windows Security events → Wazuh** (DC + client agents):
- **4625** failed logon — a spray produces a burst of 4625s across *many* accounts from one source in a short window (the signature pattern).
- **4768** TGT requested / **4771** pre-auth failed.
- **4769** service ticket requested — Kerberoasting shows **4769 with encryption type 0x17 (RC4)**, the classic roasting tell.

In Wazuh → Security events, filter the DC agent for rule groups `win_authentication_failed` and Kerberos event IDs.

![Wazuh 4625 spray burst](./02-wazuh-4625-spray.png)
> 📸 *Capture: Wazuh showing the cluster of 4625 failures across many users from one source.*

![Wazuh 4769 RC4 kerberoast](./03-wazuh-4769-kerberoast.png)
> 📸 *Capture: Wazuh event for 4769 with RC4 (0x17) encryption — the Kerberoasting indicator.*

**Sysmon** adds process context (the tool's process, network connections to the DC) for the full picture.

---

## 3. Triage

For the spray: one source → many target accounts → some failures, maybe one success (pivot immediately if 4624 success follows). For roasting: which SPN accounts were requested with RC4, and are those service accounts using weak passwords? Both go into a TheHive case; the source host and any cracked account are key observables.

---

## 4. Mitigation & remediation

- **Account lockout policy** + **MFA** blunt spraying.
- **Strong, long, rotated service-account passwords** — or **gMSA** (managed service accounts) — defeat practical Kerberoasting.
- **Disable RC4**, enforce **AES** for Kerberos.
- **Monitor 4625 spikes** and **4769 RC4** as standing detections.
- **Tiered admin model** so a cracked service account isn't domain-wide.

---

## 5. Detection engineering

- Wazuh correlation: *4625 across ≥ N distinct accounts from one source within M minutes* → "password spray" alert (a great custom rule).
- Alert on any **4769 with encryption_type 0x17** for sensitive SPNs.
- Sigma rules exist for both — port them in and tune.

---

## Screenshots checklist
- [ ] `01-spray-kerberoast.png` — attack output
- [ ] `02-wazuh-4625-spray.png` — 4625 spray burst in Wazuh
- [ ] `03-wazuh-4769-kerberoast.png` — 4769 RC4 roasting indicator
