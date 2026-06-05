# 01 — Network Foundation & Access

Builds the VPC, subnets, gateways, routing, security groups, key pair, and bastion that everything else sits on. **Console-only (no Terraform).** Region used in this build: `us-west-1` (any single region works — stay in one).

> **Do this first.** Nothing else works until the network and bastion are in place.

---

## 0. Account prep

1. **Set a billing budget/alert.** Billing & Cost Management → **Budgets** → Create a monthly cost budget (e.g. $200) with email alerts at 80% and 100%. This lab can cost real money if left running — see [cost notes](#cost--teardown).
2. **Create an EC2 key pair.** EC2 → **Key Pairs** → Create key pair → name `SOC-Analyst-Bastion-Key`, type **RSA**, format **.pem**. Download it and `chmod 400 SOC-Analyst-Bastion-Key.pem`. This single key is reused for every Linux instance in the lab.
3. **Find your public IP** (search "what is my IP") — you'll restrict bastion SSH to it. Call it `YOUR_IP/32`.

---

## 1. VPC

VPC console → **Your VPCs** → Create VPC → **VPC only**:
- Name: `soc-lab-vpc`
- IPv4 CIDR: `10.0.0.0/16`
- Tenancy: Default

After creating, select it → Actions → **Edit VPC settings** → enable **DNS hostnames** and **DNS resolution**.

---

## 2. Subnets

VPC → **Subnets** → Create subnet → select `soc-lab-vpc`. Create all five **in the same Availability Zone** (avoids cross-AZ charges):

| Name | CIDR | Purpose |
|---|---|---|
| `public-subnet` | `10.0.1.0/24` | Bastion, NAT |
| `secops-subnet` | `10.0.10.0/24` | Wazuh, Security Onion, TheHive/Cortex, Nessus |
| `attack-subnet` | `10.0.20.0/24` | Kali |
| `ad-subnet` | `10.0.30.0/24` | Domain Controller, Windows clients |
| `vuln-subnet` | `10.0.40.0/24` | Vulnerable apps host (Docker) |

Select `public-subnet` → Actions → **Edit subnet settings** → enable **Auto-assign public IPv4**. (Leave the others off — they stay private.)

---

## 3. Internet Gateway & NAT

**Internet Gateway:** VPC → **Internet Gateways** → Create → name `soc-lab-igw` → Actions → **Attach to VPC** → `soc-lab-vpc`.

**NAT** (so private instances can pull packages/updates but accept no inbound). Pick one:
- **NAT Gateway** (managed, ~$32/mo + data): VPC → **NAT Gateways** → Create → subnet `public-subnet`, Public connectivity, allocate an Elastic IP.
- **NAT instance** (cheap, ~$4/mo on t3.micro): launch a `t3.micro` Amazon Linux in `public-subnet`, disable **source/destination check** (Actions → Networking), and configure IP forwarding + iptables masquerade. Stop it when not patching to save money.

---

## 4. Route tables

**Public RT:** Create `public-rt` → Routes → add `0.0.0.0/0` → target **Internet Gateway** (`soc-lab-igw`) → Subnet associations → associate `public-subnet`.

**Private RT:** Create `private-rt` → Routes → add `0.0.0.0/0` → target **NAT Gateway** (or the NAT instance's ENI) → Subnet associations → associate `secops-subnet`, `attack-subnet`, `ad-subnet`, `vuln-subnet`.

---

## 5. Security groups (the real perimeter)

EC2 → **Security Groups** → Create (all in `soc-lab-vpc`).

**`sg-bastion`**
- Inbound: SSH (22) from `YOUR_IP/32` only. (Optional: RDP 3389 from `YOUR_IP/32`.)
- Outbound: all.

**`sg-internal`** (most private instances)
- Inbound: SSH (22) from `sg-bastion`; RDP (3389) from `sg-bastion`; **all traffic from `10.0.0.0/16`** (lab boxes talk freely — intentional).
- Outbound: all.

**`sg-secops`** (Wazuh / Security Onion / TheHive-Cortex / Nessus)
- Inbound: from `sg-bastion` (22 + web UIs 443/9000/8834/etc.); from `10.0.0.0/16` for agent traffic (Wazuh 1514/1515) and tool ports; **UDP 4789 from `10.0.0.0/16`** for VXLAN traffic-mirror traffic into Security Onion.
- Outbound: all.

**Golden rule:** nothing allows inbound from `0.0.0.0/0` except `sg-bastion` SSH from *your* IP. Vulnerable targets never face the internet.

> A dedicated SG `securityonion-trafficmirroring` for the SO sniff interface is created later in [05 — Security Onion](./05-security-onion.md): inbound **UDP 4789** + **All ICMP-IPv4** from `10.0.0.0/16`.

---

## 6. Bastion host

EC2 → Launch instances:
- Name: `bastion`
- AMI: **Amazon Linux 2023**
- Type: `t3.micro`
- Key pair: `SOC-Analyst-Bastion-Key`
- Network: `soc-lab-vpc` / `public-subnet`, **Auto-assign public IP: Enable**
- SG: `sg-bastion`

Test: `ssh -i SOC-Analyst-Bastion-Key.pem ec2-user@<bastion-public-ip>`.

---

## 7. Tunneling reference (how you reach everything private)

Private web UIs are reached by SSH local-forward through the bastion. The first number is your **local** port (your choice, must be unique); the rest is the target's real address:port.

```bash
# Combined example: Wazuh, TheHive, Cortex at once
ssh -i "SOC-Analyst-Bastion-Key.pem" \
  -L 8443:10.0.10.125:443 \   # Wazuh   -> https://localhost:8443
  -L 7443:10.0.10.29:443  \   # TheHive -> https://localhost:7443
  -L 9443:10.0.10.29:9443 \   # Cortex  -> https://localhost:9443
  ec2-user@<bastion-public-ip>
```

- **RDP to Windows:** `-L 13389:10.0.30.83:3389` then point an RDP client (not a browser) at `localhost:13389`.
- **Security Onion** uses a **SOCKS proxy** instead of `-L` (IP-based access breaks plain port-forwards): `ssh -i key -D 9999 ec2-user@<bastion>` then set the browser's SOCKS5 proxy to `localhost:9999`. See [05 — Security Onion](./05-security-onion.md).

Run these on your **local machine**, not from inside the bastion.

---

## Cost & teardown

**Cost:** ~10 instances; 24/7 ≈ $700–1,100+/mo (Security Onion is the biggest driver). Stop instances when idle; use a single AZ; NAT instance over gateway; gp3 EBS.

**Teardown order** (reverse of build, to avoid dependency errors): terminate instances → delete traffic-mirror sessions/targets/filters → release Elastic IPs → delete NAT → detach/delete IGW → delete subnets/route tables → delete the VPC.

---

## Verification checklist

- [ ] `ssh` to the bastion succeeds from your IP (and only your IP).
- [ ] A private instance can reach the internet outbound (`curl https://example.com` via NAT).
- [ ] A test SSH local-forward to a private host's port works.
- [ ] No SG allows `0.0.0.0/0` inbound except `sg-bastion` SSH.
