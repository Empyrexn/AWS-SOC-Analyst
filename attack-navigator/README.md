# ATT&CK Coverage Layer

[`soc-lab-coverage.json`](./soc-lab-coverage.json) is a [MITRE ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/) layer highlighting every technique the lab demonstrates and detects. Each highlighted cell maps to an end-to-end walkthrough in [`../attacks/`](../attacks/).

## View it

1. Open the **[ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/)**.
2. **Open Existing Layer → Upload from local** → choose `soc-lab-coverage.json`.
3. The matrix loads with the lab's techniques shaded green. Hover any highlighted cell to read which walkthrough covers it (`WT01`–`WT08`) and how it's detected.

## Techniques covered

| Tactic | Technique | Walkthrough |
|---|---|---|
| Reconnaissance | T1595 Active Scanning | 01 |
| Discovery | T1046 Network Service Discovery | 01 |
| Initial Access | T1190 Exploit Public-Facing Application | 03, 04, 05 |
| Credential Access | T1110.001 Brute Force: Password Guessing | 02 |
| Credential Access | T1110.003 Brute Force: Password Spraying | 06 |
| Credential Access | T1558.003 Kerberoasting | 06 |
| Credential Access | T1003.001 OS Credential Dumping: LSASS Memory | 07 |
| Command & Control | T1071 Application Layer Protocol | 08 |
| Discovery | T1082 System Information Discovery | 08 |
| Discovery | T1057 Process Discovery | 08 |
| Discovery | T1033 System Owner/User Discovery | 08 |
| Discovery | T1016 System Network Configuration Discovery | 08 |
