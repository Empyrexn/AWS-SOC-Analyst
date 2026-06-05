# 05 — Security Onion + VPC Traffic Mirroring

Network security monitoring: Suricata (IDS), Zeek (protocol metadata), and full packet capture. Fed by AWS **VPC Traffic Mirroring**, which copies traffic from each source instance's network interface to Security Onion's dedicated sniffing interface — detection without touching the endpoints.

This build: SO management at **10.0.10.123** (`ens5`); sniff interface **`ens6` / 10.0.10.138** (the ENI named `SO-Sniff-NI`, which is the mirror target).

---

## 1. Launch (free self-install)

Security Onion is a **free self-install** — no paid Marketplace AMI needed.
- AMI: **Oracle Linux 9**
- Type: `r5.xlarge` (32 GB RAM — SO is the lab's biggest box)
- **Storage: 250 GB gp3, set at launch** (resizing later is painful)
- Subnet: `secops-subnet` (10.0.10.0/24), **no public IP**
- SG: `sg-secops`
- Key: `SOC-Analyst-Bastion-Key`

> **Nitro requirement:** both the SO target and every mirror **source** must be Nitro instance types (`t3`, `m5`, `c5`, `r5`, …). **`t2` cannot be a mirror source.**

---

## 2. The sniffing interface (second ENI)

EC2 → **Network Interfaces** → Create network interface in `secops-subnet`:
- Name it `SO-Sniff-NI`
- SG: a dedicated `securityonion-trafficmirroring` group with inbound **UDP 4789** + **All ICMP-IPv4** from `10.0.0.0/16`

Attach it to the Security Onion instance as a **secondary** interface. Inside the OS this appears as `ens6` (the primary/management NIC is `ens5`). The private IP on this build was `10.0.10.138`.

---

## 3. Install — the clean-install gotcha (cron first!)

**The first install failed.** Oracle Linux minimal lacks `cron`, and `so-setup` cascaded into Salt master/minion handshake failures, a missing `salt` hosts entry, and a minion ID that didn't match SO's role-based top file ("No Top file or master_tops data matches found"). A network install that aborts mid-run leaves core config half-written and is unreliable to hand-repair.

**Fix = install `cronie` BEFORE running so-setup on a clean instance:**

```bash
sudo dnf install -y cronie && sudo systemctl enable --now crond
sudo dnf install -y git
git clone -b 2.4/main https://github.com/Security-Onion-Solutions/securityonion
cd securityonion
sudo bash so-setup-network
```

### Setup wizard answers (this build)
- Install type: **EVAL**
- **Management interface:** the primary NIC (`ens5`), DHCP
- **Monitor interface:** the secondary sniff NIC (`ens6`) — **press SPACEBAR to select it**
- Hostname: short (e.g. `securityonion`)
- Internet: **Direct**
- Docker IP range: default
- Web access: the **management IP** (`10.0.10.123`)
- Allowed analyst IP/CIDR: `10.0.0.0/16`

Let it run to completion. `sudo so-status` should show all services healthy and the grid **GREEN**.

### Create a web login
```bash
sudo so-user add <your-email>
```

---

## 4. Access the SO web UI (SOCKS, not -L)

Security Onion's UI is IP-bound; a plain `-L` forward breaks it. Use a **SOCKS proxy**:
```bash
ssh -i SOC-Analyst-Bastion-Key.pem -D 9999 ec2-user@<bastion-public-ip>
# set the browser's SOCKS5 proxy to localhost:9999, then browse https://10.0.10.123
```

---

## 5. VPC Traffic Mirroring

VPC console → **Traffic Mirroring**:

1. **Mirror target** → Create → `so-sniff-target` → type **Network Interface** → select **`SO-Sniff-NI`** (the ENI with `10.0.10.138` / `ens6` — **not** the management ENI).
2. **Mirror filter** → Create → `mirror-all`:
   - Inbound rule: number `100`, **accept**, **All protocols**, source `0.0.0.0/0`, dest `0.0.0.0/0`
   - Outbound rule: same
3. **Mirror session** → Create **one per source ENI** you want to watch — the vuln host, the DC, client01, client02. Each session = source ENI + target `so-sniff-target` + filter `mirror-all` + a unique session number.

AWS encapsulates mirrored packets in **VXLAN over UDP 4789** to the target.

### Verify packets are arriving
On the SO host, sniff the **Linux interface name** (`ens6`), not the `eni-...` ID:
```bash
sudo tcpdump -ni ens6 udp port 4789
```
You should see VXLAN traffic when the sources are active.

### VXLAN decapsulation
Suricata/Zeek **auto-decode** the standard VXLAN encapsulation here — no manual decap interface was needed. Fallback if a tool ever doesn't auto-decode:
```bash
ip link add vxlan0 type vxlan id <vni> dev ens6 dstport 4789
```

Then confirm real traffic appears in the SO **Hunt** interface.

---

## Verification checklist

- [ ] `sudo so-status` healthy; grid GREEN; UI reachable via SOCKS.
- [ ] `SO-Sniff-NI` (`ens6`) is the mirror target, not the mgmt ENI.
- [ ] `tcpdump -ni ens6 udp port 4789` shows VXLAN traffic.
- [ ] All four source ENIs have a mirror session.
- [ ] Generate an attack from Kali → it appears in SO **Hunt**.
