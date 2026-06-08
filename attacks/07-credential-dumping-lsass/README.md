# 07 - LSASS Credential Dumping

**MITRE ATT&CK:** T1003.001 OS Credential Dumping: LSASS Memory
**Status:** VALIDATED - dump succeeded immediately; the *detection* was the hard part, closed with a **custom Wazuh rule (100110)** after arming Sysmon ProcessAccess
**Attacker:** elevated session on the DC `dc01` / `soc.lab` (`10.0.30.83`, Windows Server 2022) - post-exploitation, local admin
**Detection:** Sysmon **EID 10 (ProcessAccess)** -> Wazuh (DC agent)

This walkthrough is deliberately **detection-centric.** Dumping LSASS is the pivot from one foothold to domain-wide compromise, so the value here isn't the dump - that worked on the first try - it's the long, honest road to actually *seeing* it. Getting the telemetry took three escalating fixes, and that journey is the whole point: **you cannot alert on what the sensor was never armed to collect.**

---

## 1. The attack - comsvcs LOLBAS MiniDump

No third-party tool, no Mimikatz binary on disk. A built-in, signed Windows DLL (`comsvcs.dll`) exposes a `MiniDump` export that will dump any process by PID - the classic living-off-the-land LSASS dump:

```powershell
rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump 632 C:\Windows\Temp\lsass.dmp full
```

(`632` is the LSASS PID.) It worked first try - a ~140 MB dump landed on disk:

![comsvcs MiniDump - 140 MB lsass.dmp written](https://github.com/user-attachments/assets/2aa819ad-0607-4440-ac41-c9d46f6b45ff)

```
-a----   6/8/2026  5:51 PM   140519545   lsass.dmp
```

That the dump *succeeded* is itself a finding: it confirms LSASS was **not** running protected (no RunAsPPL / Credential Guard) - see mitigations below.

---

## 2. The detection problem - no telemetry to alert on

The plan was Sysmon **EID 10 (ProcessAccess)** -> Wazuh. But the first check found **zero EID 10 events**. Sysmon's recent event distribution showed plenty of EID 1/3/11/13/22 - and no `10` at all. Three layers had to be peeled back:

1. **ProcessAccess wasn't being logged.** Most community Sysmon configs (incl. SwiftOnSecurity) **deliberately omit** ProcessAccess - it's extremely high-volume. So nothing was generating EID 10.
2. **A live config reload didn't fix it.** Adding a targeted `ProcessAccess` include rule for `lsass.exe` and re-applying with `Sysmon64.exe -c <cfg>` reported "Configuration updated" - but still produced **no EID 10.** A live `-c` reload does not arm the ProcessAccess kernel object-callback.
3. **The service couldn't be restarted** to force it - `Restart-Service Sysmon64` fails ("cannot be stopped"); Sysmon marks its service non-stoppable to resist tampering.

The fix was a full **driver reinstall**, which re-arms every provider:

```powershell
Sysmon64.exe -u force
Sysmon64.exe -accepteula -i C:\Windows\Temp\sysmon-lsass.xml   # config includes ProcessAccess->lsass
```

Minimal ProcessAccess rule used:

```xml
<ProcessAccess onmatch="include">
  <TargetImage condition="image">lsass.exe</TargetImage>
</ProcessAccess>
```

Re-dump, and **EID 10 finally fired** - textbook signature:

```
SourceImage:   C:\Windows\system32\rundll32.exe
TargetImage:   C:\Windows\system32\lsass.exe
GrantedAccess: 0x1410   (PROCESS_QUERY_INFORMATION | PROCESS_VM_READ - the read mask)
GrantedAccess: 0x1FFFFF (PROCESS_ALL_ACCESS)
CallTrace:     ... dbgcore.dll (MiniDumpWriteDump) ... comsvcs.dll ... rundll32.exe
SourceUser:    SOC\Administrator
TargetUser:    NT AUTHORITY\SYSTEM
```

The `CallTrace` through **`dbgcore.dll!MiniDumpWriteDump`** and **`comsvcs.dll`** is the LOLBAS dump fingerprint; `0x1410` is the canonical credential-read access mask. **Lesson: detection coverage starts at data collection** - the rule logic was irrelevant until the sensor was actually producing the event.

---

## 3. The detection gap - and the custom rule that closes it

With EID 10 flowing, Wazuh still raised **no alert.** Its built-in Sysmon Event-10 rule is **`61612` at level 0 (silent)** - confirmed straight from the shipped ruleset (`0595-win-sysmon_rules.xml`):

```xml
<rule id="61612" level="0">
  <if_sid>61600</if_sid>
  <field name="win.system.eventID">^10$</field>
  <description>Sysmon - Event 10: ... process accessed by ...</description>
</rule>
```

ProcessAccess is decoded but deliberately not alerted (far too noisy raw). So I authored a custom rule that chains off `61612` and fires only when the **target is `lsass.exe`** *and* the **GrantedAccess is a credential-read mask** - the host-side twin of the Kerberoasting rule from [WT06](../06-ad-password-spray-kerberoast/):

```xml
<rule id="100110" level="12">
  <if_sid>61612</if_sid>
  <field name="win.eventdata.targetImage" type="pcre2">(?i)\\lsass\.exe$</field>
  <field name="win.eventdata.grantedAccess" type="pcre2">(?i)^0x(1010|1410|1438|143a|1fffff|1f1fff|1f2fff)$</field>
  <description>Possible LSASS credential dumping (T1003.001): $(win.eventdata.sourceImage) opened a handle to lsass.exe (GrantedAccess $(win.eventdata.grantedAccess))</description>
  <mitre><id>T1003.001</id></mitre>
</rule>
```

**One more gotcha before it lit up:** after deploying the rule it *still* fired nothing. The Sysmon uninstall/reinstall had recreated the `Microsoft-Windows-Sysmon/Operational` channel, which **orphaned the Wazuh agent's event-channel subscription** - the agent was up but reading a dead handle. A `Restart-Service WazuhSvc` re-subscribed it. Then the re-dump fired **rule 100110 at level 12:**

![Wazuh custom rule 100110 fires - level 12, LSASS dumping detected](https://github.com/user-attachments/assets/2209a6c2-e815-4ad8-8b53-37bdff1167d9)

```
Possible LSASS credential dumping (T1003.001): C:\Windows\system32\rundll32.exe opened a handle to lsass.exe (GrantedAccess 0x1fffff)   rule 100110, level 12
Possible LSASS credential dumping (T1003.001): C:\Windows\system32\rundll32.exe opened a handle to lsass.exe (GrantedAccess 0x1410)     rule 100110, level 12
```

Once the agent re-subscribed, the full Sysmon pipeline came alive in the DC dashboard (`sysmon`, `sysmon_eid1_detection`, `sysmon_eid11_detection` rule groups now populating):

![Wazuh DC dashboard - Sysmon groups and level-12 alerts now flowing](https://github.com/user-attachments/assets/5a476edb-563c-4871-b8a6-586b4be1ae1a)

**Gap closed.** Full rule: [`configs/wazuh/local_rules.xml`](../../configs/wazuh/local_rules.xml).

---

## 4. Triage

Critical by default. The analyst pivots on **SourceImage**: `rundll32.exe` invoking `comsvcs.dll MiniDump` against LSASS is almost never benign, and the `CallTrace` through `dbgcore.dll` seals it. Confirm whether a dump file hit disk (Sysmon EID 11 / file-create) and whether the access chained from a shell or remote session. This is a textbook **isolate-the-host** moment, and a high-severity TheHive case keyed on the host + the offending process.

---

## 5. Mitigation & remediation

- **LSA Protection (RunAsPPL)** - run LSASS as a protected process; blocks most user-mode dumpers. (The dump here succeeded precisely *because* this wasn't on.)
- **Credential Guard** - isolates LSASS secrets in a VBS container; the strongest control.
- **ASR rule** "Block credential stealing from the LSASS subsystem."
- **Tiered admin model + LAPS** - deny attackers the local-admin rights needed to read LSASS in the first place.
- **EDR** with in-memory detection for defense in depth.
