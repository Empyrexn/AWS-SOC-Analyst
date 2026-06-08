# 08 - Caldera Adversary Emulation

**MITRE ATT&CK:** T1071 Application Layer Protocol (C2) - T1082 / T1057 / T1033 / T1016 Discovery - T1105 Ingress Tool Transfer
**Status:** VALIDATED - full chain caught across **all three layers**: network (Suricata), host (Sysmon -> Wazuh), and SOAR (TheHive)
**Attacker:** MITRE Caldera C2 (`10.0.10.29:8888`) -> Sandcat agents on Windows Server 2022 hosts - **Detection:** Security Onion + Wazuh + TheHive

The capstone. Instead of one technique, Caldera ran an automated **Discovery** profile - a chain of ATT&CK abilities - across three checked-in Sandcat agents, exercising host and network detection together and producing a realistic multi-stage incident. This is the walkthrough that ties the entire lab together: one operation, caught simultaneously at the network edge, on the endpoint, and correlated into a case.

---

## 1. The operation

Caldera 5.3.0, operation **`08-SOC-Lab-Discovery`** - the built-in **Discovery** adversary profile, `atomic` planner, **`plain-text`** obfuscator (deliberately - cleartext commands make the host telemetry readable), run autonomously against group `red`. Three Sandcat agents checked in (paws `emymhn` / `wzmcpa` / `tpxyaq`) on Server 2022 hosts `EC2AMAZ-IVIQBVU` (dc01), `-C0GQIF6`, `-TNPACDB`. All 24 ability decisions returned **success**:

![Caldera Discovery operation - abilities success across 3 agents](https://github.com/user-attachments/assets/b4816741-4b56-4d8c-a7f5-e2e49b84010e)

Visible in the run: *Identify active user* (T1033), *Identify local users*, *Find user processes* (T1057), *View admin shares*, *Discover domain controller* - the same profile also executes system-information (T1082) and network-configuration (T1016) discovery. Each agent beacons back to the C2 on its contact interval.

---

## 2. Network detection - Security Onion (T1071)

The agent's C2 traffic lit up Suricata immediately, including a **dedicated Sandcat signature at HIGH severity**:

![Security Onion - Suricata Sandcat C2 alerts](https://github.com/user-attachments/assets/f7b23682-b79c-499e-b3db-3440c11f7011)

- **`ET MALWARE Golang/Sandcat Plugin Activity (POST)` - HIGH** - fires on the Sandcat agent's POST beacons (the strongest single network signal).
- **`ET USER_AGENTS Go HTTP Client User-Agent`** and **`ET INFO Go-http-client User-Agent Observed Outbound/Inbound`** - the Go runtime user-agent that Sandcat is built on.

These repeat at a **regular cadence** - that fixed-interval heartbeat to one destination (`10.0.10.29:8888`) is the network fingerprint of C2 beaconing (T1071).

---

## 3. Host detection - Sysmon -> Wazuh (T1105 + discovery)

On the endpoint, Wazuh caught the chain via Sysmon:

![Wazuh dc01 - file drop (lvl 15) + WMI AV discovery](https://github.com/user-attachments/assets/4733ef37-6164-46cd-85b6-d44100ba861e)

![Wazuh dc01 dashboard - Sysmon groups + level-12 alerts](https://github.com/user-attachments/assets/971a0870-2519-4936-83de-fe762ec03a97)

- **`92213` "Executable file dropped in folder commonly used by malware" - level 15** (Sysmon **EID 11**) - the Sandcat binary (`splunkd.exe`) written to `C:\Users\Public`. That maps to **T1105 Ingress Tool Transfer** and is the highest-severity alert of the whole run.
- **`92077` "WMI command was used for AV product discovery" - level 10** - the *Identify Antivirus* ability's WMI query. **This is the standout detail:** that ability actually **errored** (see section 5), yet the attempt was still detected. You catch the behavior, not just the result.
- The discovery commands generate a **Sysmon EID 1** process-create burst parented to the agent, and **EID 3** connections to the C2 - both now flowing (the `sysmon`, `sysmon_eid1_detection`, `sysmon_eid11_detection` rule groups populate the dashboard).

---

## 4. SOAR correlation - TheHive (the pipeline end to end)

The level-15 drop alert crossed the `level >= 7` threshold and **auto-created TheHive case #4** with no analyst action:

![TheHive case #4 - auto-created from the Wazuh level-15 drop alert](TheHive" src="https://github.com/user-attachments/assets/cb9022ae-4195-4f5f-851b-5bc621017ada)

```
Case #4  "Executable file dropped in folder commonly used by malware"   SEVERITY: HIGH
Wazuh rule 92213, level 15  |  MITRE T1105 (Ingress Tool Transfer), tactic Command and Control
agent client01 (10.0.30.58)  |  Detection < 1 second  |  Triage 3m 21s
```

This is the **Wazuh -> TheHive SOAR pipeline** ([WT02](../02-ssh-brute-force/) proved it on brute force; here it triggers off endpoint EID 11) closing the loop on the emulation automatically.

---

## 5. The ability that "failed" - and was caught anyway

Two ability instances errored with `Description = Invalid namespace`. The command:

```powershell
Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct ...
```

`root\SecurityCenter2` is populated by the Windows **Security Center** service, which exists **only on client SKUs (Windows 10/11)** - **Windows Server has no such namespace.** Every Caldera agent here is on Server 2022, so the query can't resolve and returns "Invalid namespace." It's an environment mismatch (a workstation ability run against servers), not a deployment fault. Crucially, Wazuh's **rule 92077** fired on the WMI call regardless - **the failed technique still produced a detection.** That's exactly the resilience a SOC wants: alert on the attempt, not just on success.

---

## 6. Triage

This is the multi-stage incident the whole lab exists to practice. Rebuild the sequence from correlated evidence: **agent dropped** (`splunkd.exe`, EID 11 / T1105) -> **C2 beacon established** (Suricata Sandcat POST / T1071) -> **discovery chain** (EID 1 burst / T1082, T1057, T1033, T1016) -> bonus recon (admin shares, domain-controller discovery). The anchor observables are the dropped binary and the beacon destination `10.0.10.29:8888`. TheHive case #4 is the starting point; an analyst promotes it, attaches the network and host evidence, and reconstructs one timeline.

---

## 7. Mitigation & remediation

- **Application allowlisting** to stop unsigned dropped agents (`splunkd.exe` in a public folder).
- **Egress filtering / proxy inspection** to break C2 to unsanctioned destinations.
- **Network beacon analytics** (interval + jitter) as a standing detection.
- **EDR / behavioral detection** for living-off-the-land and agent activity.
- **Least privilege** to limit what each discovery technique can enumerate.
