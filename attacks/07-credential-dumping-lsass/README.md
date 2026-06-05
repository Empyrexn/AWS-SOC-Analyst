# 07 — LSASS Credential Dumping

**MITRE ATT&CK:** T1003.001 OS Credential Dumping: LSASS Memory
**Attacker:** on a compromised Windows endpoint (post-exploitation) · **Detection:** Sysmon EID 10 → Wazuh

Reading credentials out of LSASS is one of the most important detections a SOC can have — it's the pivot from a single foothold to domain-wide compromise. This walkthrough is deliberately **detection-centric**: the value is the telemetry and the mitigation, not the dumping.

---

## 1. The attack (post-exploitation)

On a Windows endpoint you already control (e.g., via the Caldera agent or an RDP session as a local admin), an attacker accesses LSASS memory to harvest credentials — using a well-known public tool such as Mimikatz (`sekurlsa::logonpasswords`) or by creating an LSASS process dump. The point for the lab is to **generate the LSASS-access telemetry**, then go catch it.

![LSASS access attempt](./01-lsass-access.png)
> 📸 *Capture: the tool/command being run on the endpoint (or the dump being created). Keep this minimal — the screenshots that matter are the detections below.*

---

## 2. Detection

**Sysmon Event ID 10 (ProcessAccess) → Wazuh** is the primary signal.
- Sysmon logs when a process opens a handle to **`lsass.exe`**. Credential-dumping tools request high-access masks — watch **GrantedAccess** values like **0x1010 / 0x1410 / 0x143A** from unusual source images.
- The Sysmon channel is already collected by the default Windows Wazuh config ([docs/03](../../docs/03-wazuh.md)), so this lands in Wazuh automatically.
- In Wazuh → Security events, filter the endpoint agent for Sysmon EID 10 with `TargetImage` = `lsass.exe`.

![Sysmon EID 10 lsass access in Wazuh](./02-wazuh-sysmon-eid10-lsass.png)
> 📸 *Capture: the Wazuh event for Sysmon EID 10 targeting lsass.exe — show SourceImage, TargetImage, and GrantedAccess.*

**Supporting signals:** Sysmon **EID 1** (process create) for the dumping tool, **EID 11** (file create) if a dump file is written to disk, and Windows **4688** process creation.

![Process-create context](./03-wazuh-sysmon-process-create.png)
> 📸 *Capture: the Sysmon EID 1 / 4688 event showing the suspicious process that touched LSASS.*

---

## 3. Triage

Critical-priority by default. Identify the **SourceImage** accessing LSASS — is it a known admin tool or something dropped in a temp path? Confirm whether a dump file was written (EID 11) and whether the process was spawned by the Caldera agent / a shell. This is a classic point to **isolate the host**. Open a high-severity TheHive case with the process and host as observables.

---

## 4. Mitigation & remediation

- **Credential Guard** — isolates LSASS secrets in a VBS container (the strongest control).
- **LSA Protection (RunAsPPL)** — makes LSASS a protected process, blocking most user-mode dumpers.
- **Attack Surface Reduction rule** "Block credential stealing from the LSASS subsystem."
- **Restrict local admin** (tiered model, LAPS) so attackers can't get the rights to read LSASS.
- **EDR** with in-memory detection for defense in depth.

---

## 5. Detection engineering

- Wazuh rule on Sysmon EID 10 where `TargetImage` ends with `lsass.exe` and `GrantedAccess` is in the known dumper set, **excluding** legitimate accessors (AV/EDR) to cut false positives — a high-value tuning exercise.
- Layer EID 1/11 correlation: tool-process → LSASS access → dump-file write = very high confidence.
- Sigma has well-maintained LSASS-access rules; import and adapt.

---

## Screenshots checklist
- [ ] `01-lsass-access.png` — the dumping action (minimal)
- [ ] `02-wazuh-sysmon-eid10-lsass.png` — Sysmon EID 10 LSASS access in Wazuh
- [ ] `03-wazuh-sysmon-process-create.png` — EID 1 / 4688 process context
