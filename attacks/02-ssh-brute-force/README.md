# 02 - SSH Brute Force

**MITRE ATT&CK:** T1110.001 Brute Force: Password Guessing (bonus: T1136 Create Account)
**Status:** VALIDATED - run end-to-end, full pipeline confirmed
**Attacker:** Kali `10.0.20.23` - **Target:** Docker host sshd `10.0.40.222:22`
**Detection chain:** Wazuh (host) -> TheHive (auto-alert + observables) -> Cortex (enrichment)

This is the lab's flagship result: a single attack that travels the **entire** detection-and-response pipeline, from host telemetry to an enriched case, with no manual steps between detection and alert.

> **Why port 22, not the Metasploitable SSH on 2222?** Attack 01 taught us that the Metasploitable services run *inside a container with no agent*, so Wazuh is blind to them. The Wazuh agent lives on the Docker **host**, whose own sshd is on port 22 and logs to `auth.log` - which Wazuh's sshd decoder reads. Targeting port 22 is what makes the host pipeline fire. (Sensor placement, again.)

---

## 1. The attack

The vuln host was temporarily set to allow SSH password auth, with one weak-password account planted (`labvictim`) - the exact misconfiguration the mitigation section addresses. From Kali, 60 wrong guesses then the real password:

```bash
(for i in $(seq 1 60); do echo "wrong$i"; done; echo 'Summer2026!') > sshpw.txt
hydra -l labvictim -P sshpw.txt -s 22 ssh://10.0.40.222 -t 4 -V
```

Hydra ran all 61 attempts and **landed the credential**:

![Hydra brute force success](https://github.com/user-attachments/assets/9d3a6c81-02ed-4d2a-a0c8-32b600aa00b9)

```
[22][ssh] host: 10.0.40.222   login: labvictim   password: Summer2026!
```

This is now a **confirmed compromise**, not just an attempt - important for triage severity.

---

## 2. Detection - Wazuh (host)

The agent `ip-10-0-40-222` lit up with a burst of authentication-failure alerts. The detection is **layered** - multiple independent rules catch the same activity:

| Rule ID | Description | Level |
|---|---|---|
| 5760 | sshd: authentication failed | 5 |
| 5758 | Maximum authentication attempts exceeded | 8 |
| 5503 | PAM: User login failed | 5 |
| 2501 | syslog: User authentication failure | 5 |
| 2502 | syslog: User missed the password more than one time | 10 |
| 40111 | Multiple authentication failures (correlation) | 10 |
| 5712 | **sshd: brute force trying to get access to the system** | 10 |
| 5901 / 5902 | New user / group added to the system (the `labvictim` account -> T1136) | 8 |

![Wazuh events - layered auth-failure rules](https://github.com/user-attachments/assets/317bb260-9fad-420a-a488-481643fe28ee)

The built-in **Threat Hunting dashboard** quantifies the burst cleanly: **104 authentication failures** and **12 successes** in the window, with the spike clearly visible and the alerts mapped to **PCI DSS 10.2.x** (audit-logging requirements):

![Wazuh threat hunting dashboard](https://github.com/user-attachments/assets/f8bc7a9c-3d55-4c5a-a8d7-6b4cbc45ab62)

> The **12 authentication successes** include the moment the brute force actually worked (`labvictim` logging in with the cracked password) - the failures-then-success pattern is the signature of a *successful* brute force.

---

## 3. Automated alerting - TheHive

Because the brute-force rules are level 10 (>= the integration's threshold of 7) and the Wazuh alert carried `data.srcip`, the integration **auto-created** a TheHive alert - titled "sshd: brute force trying to get access to the system" - with **two IP observables attached automatically**: the attacker `10.0.20.23` and the target `10.0.40.222`. Created by `wazuh-integration`, detection time **< 1 second**.

![TheHive auto-created alert with observables](https://github.com/user-attachments/assets/a4b839ad-3581-4b23-8c36-a7898a177c46)

> **Triage note - alert volume.** The org accumulated ~477 alerts because the integration creates one TheHive alert per qualifying Wazuh alert. High fidelity, but noisy - in production you'd dedupe/aggregate by source + rule. A realistic tuning observation, not a defect.

---

## 4. Enrichment - Cortex

Promoting the alert to a case and running the source IP `10.0.20.23` through Cortex analyzers:

| Analyzer | Result |
|---|---|
| **IP-API** | Success - `status: private range`, country None |
| **DShield** | Success - reputation **Safe**, 0 attacks / 0 threatfeeds, AS "not routed" |
| Abuse_Finder | Failure (analyzer traceback on the private/`null` input - a real analyzer quirk, not a pipeline issue) |

![Cortex IP-API - private range](https://github.com/user-attachments/assets/c32c41bd-7e3d-49dc-85d3-14131e398803)
![Cortex DShield - safe / no threat intel](https://github.com/user-attachments/assets/f11b12e2-319c-4c71-8bd8-fd9832590325)

The enrichment verdict *sharpens* the conclusion rather than weakening it: an RFC1918 source with no public threat intel means the attacker is **internal** - consistent with a compromised host performing lateral brute force, which is a higher-priority scenario than a random external scanner.

---

## 5. Triage

Promote alert -> case. Confirmed facts: source `10.0.20.23` (internal), target `10.0.40.222`, account `labvictim`, and a **success** following the failure burst (Wazuh rule 5715 / the dashboard's 12 successes). Verdict: **brute force succeeded - treat the target as compromised** and the source as a likely-compromised internal host. Observables (both IPs) are already on the case for pivoting. The incidental `adduser` alerts (T1136) are worth noting as possible persistence.

---

## 6. Mitigation & remediation

- **Key-based auth only** - disable SSH password authentication (exactly what the lab reverts to after the test). This single control defeats the attack.
- **fail2ban** / account lockout to ban sources after N failures.
- **MFA** on SSH where feasible; kill weak passwords like `Summer2026!`.
- **Restrict SSH** to the bastion/jump host only (the lab already gates this with security groups).

---

## 7. Detection engineering

- Rules **5712** and **40111** already correlate the failure burst - tune their frequency/timeframe to the environment's noise floor.
- Add a high-value correlation: *failures from IP X followed by a success from IP X* -> a critical **"brute force succeeded"** alert (the single most important SSH detection).
- **Dedupe TheHive alerts** - aggregate by `source.ip` + rule so one campaign is one case, not hundreds of alerts.
- The integration auto-promoting `srcip`/`agent.ip` to observables is what makes Cortex enrichment one click - worth preserving.

---

## Screenshots
- [x] `01-hydra-brute-force.png` - Hydra landing the credential
- [x] `02-wazuh-bruteforce-5712.png` - Wazuh layered auth-failure rules
- [x] `02b-wazuh-dashboard.png` - Threat Hunting dashboard (104 failures, spike, PCI DSS)
- [x] `03-thehive-alert.png` - auto-created TheHive alert with both IP observables
- [x] `04-cortex-enrichment.png` - Cortex IP-API (private range)
- [x] `04b-cortex-dshield.png` - Cortex DShield (safe / no threat intel)
