# 03 — Web SQL Injection (DVWA)

**MITRE ATT&CK:** T1190 Exploit Public-Facing Application · **OWASP:** A03:2021 Injection
**Attacker:** Kali · **Target:** DVWA `10.0.40.222:8081` · **Detection:** Wazuh (container logs) + Security Onion (Suricata)

Web app attacks are the most common real-world initial-access vector. DVWA is purpose-built to be injected, and the lab captures it both at the host (Docker logs → Wazuh) and on the wire (Suricata).

---

## 1. The attack

Log into DVWA (`admin`/`password`), set security to Low, and hit the **SQL Injection** page. A classic auth/logic-break payload in the `id` field:
```
1' OR '1'='1
```
Then automate extraction with sqlmap to make it loud and realistic:
```bash
sqlmap -u "http://10.0.40.222:8081/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="PHPSESSID=<your-session>; security=low" --batch --dbs
```

![SQLi payload + result](./01-dvwa-sqli.png)
> 📸 *Capture: the DVWA page returning extra rows (or sqlmap dumping the database list).*

---

## 2. Detection

**Wazuh (Docker container logs)** — the vuln host forwards Apache/DVWA logs via the `localfile` block ([docs/03](../../docs/03-wazuh.md)). The injection requests appear as web access events; sqlmap's volume and signature-laden URIs stand out. Filter the vuln-host agent for the DVWA container and the `/vulnerabilities/sqli/` URI.

![Wazuh web log event](./02-wazuh-weblog-sqli.png)
> 📸 *Capture: the Wazuh event showing the SQLi request URI from the DVWA container log.*

**Security Onion (Suricata)** — ET WEB_SERVER / SQL-injection signatures fire on the malicious HTTP payloads crossing the mirror. Check SO **Alerts** filtered to the Kali source and the DVWA destination; Zeek `http.log` in **Hunt** shows the request URIs.

![Suricata SQLi alert](./03-securityonion-sqli-alert.png)
> 📸 *Capture: SO Suricata SQL-injection alert + the Zeek http.log entries in Hunt.*

---

## 3. Triage

Confirm method (manual vs automated — sqlmap's user-agent and request cadence are obvious), what was accessed (did it reach `--dump`?), and whether the app returned data (successful extraction vs blocked). Tag the source IP and the targeted endpoint.

---

## 4. Mitigation & remediation

- **Parameterized queries / prepared statements** — the real fix; never concatenate input into SQL.
- **Input validation & least-privilege DB account** — the app's DB user shouldn't be able to read every schema.
- **WAF** in front of the app to block injection signatures.
- **Disable verbose errors** so the app doesn't leak schema details.

---

## 5. Detection engineering

- Custom Wazuh decoder/rule to flag SQLi keywords (`UNION SELECT`, `OR 1=1`, `information_schema`) in web-log URIs → high-severity alert.
- Tune Suricata web rules to your apps; allowlist your own scanner (Nessus) to cut noise.
- Sigma rule on proxy/web logs for portability.

---

## Screenshots checklist
- [ ] `01-dvwa-sqli.png` — payload/sqlmap result
- [ ] `02-wazuh-weblog-sqli.png` — Wazuh container-log event
- [ ] `03-securityonion-sqli-alert.png` — Suricata alert + Zeek http.log
