# 02 — SSH Brute Force

**MITRE ATT&CK:** T1110.001 Brute Force: Password Guessing
**Attacker:** Kali · **Target:** Metasploitable SSH `10.0.40.222:2222` · **Detection:** Wazuh → TheHive → Cortex

This is the showcase end-to-end demo: it generates host alerts with a **source-IP observable**, which auto-flows into TheHive and gets enriched by Cortex — the full SOC pipeline in one attack.

---

## 1. The attack

From Kali, a password-guessing run against SSH (remember Metasploitable's SSH is on host port **2222**):
```bash
hydra -l msfadmin -P /usr/share/wordlists/rockyou.txt \
  -s 2222 ssh://10.0.40.222 -t 4 -V
```
This hammers the login with attempts until it lands the known-weak `msfadmin` credential.

![Hydra brute force](./01-hydra-brute-force.png)
> 📸 *Capture: Kali terminal showing Hydra's attempts and the successful credential hit.*

---

## 2. Detection

**Wazuh** is built for exactly this — repeated auth failures from one source.
- Individual failures map to SSHD rules (e.g. **5710** non-existent user, **5760** failed password).
- The composite rule **5712 — "SSHD brute force trying to get access to the system"** fires once the failure rate crosses threshold. That's your high-signal alert (level ≥ 10).
- In the Wazuh dashboard → **Security events**, filter by the vuln-host agent and rule group `authentication_failed` / `5712`.

![Wazuh brute-force alert](./02-wazuh-bruteforce-5712.png)
> 📸 *Capture: the Wazuh event detail for rule 5712 showing the source IP, agent, and failure count.*

**TheHive** — because rule 5712 is ≥ level 7 **and** the Wazuh alert carries `data.srcip`, the integration auto-creates an alert with the attacker IP as an **observable** (see [docs/07](../../docs/07-wazuh-thehive-integration.md)).

![TheHive auto-created alert](./03-thehive-alert.png)
> 📸 *Capture: the TheHive alert (logged in as an org user) with the Wazuh title and the srcip observable.*

**Cortex** — promote the alert to a case and run the source IP through analyzers (AbuseFinder, DShield, TorProject). Internal IPs correctly return "private range"; the workflow is what matters.

![Cortex enrichment](./04-cortex-enrichment.png)
> 📸 *Capture: the Cortex analyzer report on the IP observable inside the TheHive case.*

---

## 3. Triage

Promote alert → case. Confirm the source (internal `10.0.20.x` = the Kali pivot). Note the targeted account and whether any attempt **succeeded** (Wazuh rule 5715 "successful login" right after a burst of failures = compromise, not just an attempt). Document timeline in the case.

---

## 4. Mitigation & remediation

- **Key-based auth only** — disable password auth (`PasswordAuthentication no`).
- **fail2ban** — auto-ban source IPs after N failures.
- **Account lockout** thresholds; **MFA** where supported.
- **Restrict exposure** — SSH reachable only from a bastion/jump host (the lab already does this).
- **Strong/rotated credentials** — kill default creds like `msfadmin`.

---

## 5. Detection engineering

- Tune 5712's frequency/timeframe in `local_rules.xml` to your noise floor.
- Add a correlation: *failures from IP X, then a success from IP X* → critical "brute force succeeded" rule.
- Sigma equivalent for portability across SIEMs.

---

## Screenshots checklist
- [ ] `01-hydra-brute-force.png` — Hydra run + hit
- [ ] `02-wazuh-bruteforce-5712.png` — Wazuh rule 5712
- [ ] `03-thehive-alert.png` — auto-created TheHive alert w/ observable
- [ ] `04-cortex-enrichment.png` — Cortex analyzer report
