# 08 — Caldera Adversary Emulation

**MITRE ATT&CK:** multi-technique chain (Discovery → Collection → C2) · T1071 Application Layer Protocol (C2)
**Attacker:** MITRE Caldera (`10.0.10.29:8888`) → Sandcat agents on endpoints · **Detection:** Sysmon/Wazuh + Security Onion

The capstone. Instead of one technique, Caldera runs a *chain* of ATT&CK abilities automatically, exercising host and network detection together and producing a realistic multi-stage incident — exactly what a SOC sees.

---

## 1. The attack

With Sandcat agents checked in (see [docs/08](../../docs/08-caldera.md)), launch an operation:
- Caldera UI (login `red`) → **Operations → Create Operation**
- Pick an **adversary profile** (a built-in chain — e.g. discovery + collection abilities)
- Target the `red` agent group → **Start**

Caldera executes the abilities in sequence and reports each technique with its ATT&CK ID — and the agent **beacons back** to the C2 server on its contact interval.

![Caldera operation running](./01-caldera-operation.png)
> 📸 *Capture: the Caldera operation view showing executed abilities and their ATT&CK technique IDs.*

---

## 2. Detection

**Sysmon → Wazuh (host)** — each ability leaves endpoint telemetry:
- **EID 1** process creation for every command the agent runs (the parent chain traces back to the Sandcat process, `splunkd.exe` in `C:\Users\Public`).
- **EID 3** network connections to the C2 (`10.0.10.29:8888`).
- Discovery commands (whoami, net, systeminfo, etc.) light up as a cluster from one process.

![Wazuh Sysmon ability chain](./02-wazuh-sysmon-chain.png)
> 📸 *Capture: Wazuh showing the burst of Sysmon EID 1 process-creates from the agent, with the suspicious parent.*

**Security Onion (network)** — the agent's periodic beaconing to the C2 is detectable as **regular, fixed-interval connections** (low-jitter heartbeat) to one destination. Zeek `conn.log` in **Hunt** makes the beacon cadence visible; Suricata may flag the C2 pattern.

![Security Onion C2 beacon](./03-securityonion-c2-beacon.png)
> 📸 *Capture: SO Hunt showing the repeating beacon connections to 10.0.10.29:8888 (the C2).*

**TheHive** — any ability that trips a level ≥ 7 Wazuh rule auto-creates an alert; promote to a case and reconstruct the kill chain from the correlated host + network evidence.

![TheHive case kill-chain](./04-thehive-case.png)
> 📸 *Capture: the TheHive case tying the emulation's alerts together.*

---

## 3. Triage

This is multi-stage: map each observed technique back to ATT&CK and rebuild the sequence (foothold → discovery → collection → C2). The beaconing destination and the Sandcat process are the anchor observables. Practicing this correlation — host telemetry + network beacon + single timeline — is the core SOC skill the whole lab exists to build.

---

## 4. Mitigation & remediation

- **EDR / behavioral detection** for agent and living-off-the-land activity.
- **Egress filtering** — block/inspect outbound to unsanctioned destinations to break C2.
- **Application allowlisting** to stop unsigned agents like the dropped binary.
- **Network detection of beaconing** (interval/jitter analytics) as a standing capability.
- **Least privilege** to limit what each technique can accomplish.

---

## 5. Detection engineering

- Build a beacon-detection analytic on Zeek `conn.log`: same src→dst, near-constant interval, many connections → "possible C2 beacon."
- Wazuh rule for known LOLBins spawned by an unusual parent (the agent).
- Map your detections to an **ATT&CK Navigator** layer to visualize coverage — a strong portfolio artifact in itself.

---

## Screenshots checklist
- [ ] `01-caldera-operation.png` — operation + ATT&CK IDs
- [ ] `02-wazuh-sysmon-chain.png` — Sysmon process-create burst in Wazuh
- [ ] `03-securityonion-c2-beacon.png` — beacon cadence in SO Hunt
- [ ] `04-thehive-case.png` — correlated TheHive case
