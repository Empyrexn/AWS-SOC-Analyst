# 03 - Web SQL Injection (DVWA)

**MITRE ATT&CK:** T1190 Exploit Public-Facing Application - **OWASP:** A03:2021 Injection
**Status:** VALIDATED - network detection confirmed; host-layer blind spot documented
**Attacker:** Kali `10.0.20.23` - **Target:** DVWA `10.0.40.222:8081`
**Primary detection:** Security Onion / Suricata - **Host detection (Wazuh):** none (see Section 3)

Web-app injection is the most common real-world initial-access vector. This run shows Security Onion catching it cleanly on the wire - and confirms that the *host* SIEM is blind to it, which is an important architecture lesson about where web-attack detection has to live.

---

## 1. The attack

DVWA was set to **security = low**. The session was minted from Kali with `curl` first: DVWA's login form carries an anti-CSRF `user_token`, so a raw cookie-paste fails (the first sqlmap attempt 302-redirected to `login.php` because the pasted `PHPSESSID` wasn't authenticated). With a valid session, sqlmap ran against the `id` parameter:

```bash
sqlmap -u "http://10.0.40.222:8081/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="PHPSESSID=<authed-session>; security=low" --batch --dbs
```

sqlmap confirmed the `id` parameter injectable via **four** techniques and enumerated the databases:

- **boolean-based blind** - `id=1' OR NOT 3910=3910#`
- **error-based** - `EXTRACTVALUE(...)`
- **time-based blind** - `... AND (SELECT ... SLEEP(5))`
- **UNION query** - 2 columns
- Back-end: **MySQL >= 5.1 (MariaDB fork)**; stack: Apache 2.4.25 / Debian 9
- Databases found: **`dvwa`**, **`information_schema`** (and the user table was within reach via `-D dvwa -T users --dump`)

![sqlmap injection + database enumeration](https://github.com/user-attachments/assets/33910e94-3015-46f6-89f2-b306df2700cd)

---

## 2. Detection - Security Onion (Suricata)

Three signatures fired from `10.0.20.23 -> 10.0.40.222:8081`:

| Signature | SID | Severity | What it caught |
|---|---|---|---|
| ET SCAN Sqlmap SQL Injection Scan | 2008538 | medium | the **sqlmap tool** itself (traffic fingerprint) |
| ET WEB_SERVER Possible MySQL SQLi Attempt Information Schema Access | 2017808 | **high** | the `information_schema` enumeration (`--dbs`) |
| ET WEB_SERVER Possible SQL Injection SELECT CAST in HTTP URI | 2053467 | **high** | SQL-injection payload structure in the URI |

![Security Onion SQLi alerts](https://github.com/user-attachments/assets/f2754506-d78e-44dc-b66d-8de40cc1cc14)

Two complementary detection styles in one attack: **tool attribution** (2008538 fingerprints sqlmap's traffic - the same idea as the Nmap User-Agent rule in [WT01](../01-network-recon-nmap/)) plus **technique/payload detection** (the high-severity `information_schema` and `SELECT CAST` rules). Suricata inspects HTTP regardless of port, so traffic to `8081` still triggers the `ET WEB_SERVER` ruleset.

---

## 3. Host layer - the Wazuh blind spot (the finding)

**Wazuh produced no SQL-injection or web-application alerts for this attack.** Filtering the vuln-host agent over the period shows only SSH/auth activity left over from the earlier brute-force test - zero web alerts:

![Wazuh - no web-attack alerts](https://github.com/user-attachments/assets/0581f8bd-2880-4b7b-a185-f84e5cd36280)

> The dashboard above is dominated by the [WT02](../02-ssh-brute-force/) auth data on purpose - it's the proof that **nothing web-related reached Wazuh**.

**Why:** DVWA runs inside a Docker container. The agent's Docker collection reads container `*-json.log` (stdout/stderr), but DVWA's Apache access logs don't surface there in a form Wazuh's rules flag - so a network-borne attack against a containerized web app is invisible to the host SIEM here. Same host-vs-network lesson as WT01, now for **exploitation** rather than recon.

**Architectural takeaway:** to see web attacks at the SIEM you need either network IDS (Security Onion, which worked) or **application/WAF log forwarding** into Wazuh. Network monitoring isn't optional - it's the only thing that caught this.

---

## 4. Triage

Confirmed SQL injection with **data access** - the back-end DB was enumerated and the `dvwa.users` table (password hashes) was reachable. Source `10.0.20.23` (internal). The combination of the **sqlmap tool-attribution** alert and the **information_schema access** alert from one source is a high-confidence "active SQLi tool dumping the database" signal. Escalate; treat the application database as exposed.

---

## 5. Mitigation & remediation

- **Parameterized queries / prepared statements** - the real fix; never concatenate input into SQL.
- **Least-privilege DB account** - the app's user shouldn't be able to read `information_schema` or other schemas.
- **Input validation** and **disable verbose SQL errors** (kills error-based extraction).
- **WAF** in front of the app to block injection signatures.
- DVWA's **"Impossible"** security level uses prepared statements - re-running sqlmap against it shows the injection fail, a clean before/after demonstration of the fix.
