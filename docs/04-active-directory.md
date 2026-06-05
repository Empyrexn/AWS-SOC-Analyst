# 04 — Active Directory

A Windows Server 2022 forest (`soc.lab`) with domain-joined Windows clients — a realistic enterprise identity environment to attack (from Kali/Caldera) and monitor (Wazuh + Sysmon).

This build: DC at **10.0.30.83**, domain **soc.lab**, NetBIOS **SOC**, login `SOC\Administrator`.

---

## 1. Launch the Domain Controller

EC2 → Launch:
- AMI: **Microsoft Windows Server 2022 Base** (AWS-provided, license-included)
- Type: `t3.large`+
- Subnet: `ad-subnet` (10.0.30.0/24), **no public IP**
- SG: `sg-internal` (RDP 3389 from `sg-bastion`)
- Key: `SOC-Analyst-Bastion-Key`

### Get in via RDP
Decrypt the admin password (EC2 → select instance → **Connect → RDP client → Get password**, upload the `.pem`), then tunnel RDP through the bastion:
```bash
ssh -i SOC-Analyst-Bastion-Key.pem -L 13389:10.0.30.83:3389 ec2-user@<bastion-public-ip>
# RDP client -> localhost:13389, user Administrator + decrypted password
```

---

## 2. Promote to a Domain Controller

In Server Manager → **Add roles and features** → install **Active Directory Domain Services**. Then click the post-deploy flag → **Promote this server to a domain controller**:
- **Add a new forest** → Root domain name: `soc.lab`
- Set a DSRM password
- Accept defaults; let it set the NetBIOS name (`SOC`) → finish and reboot.

PowerShell equivalent for the promotion step:
```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "soc.lab" -DomainNetbiosName "SOC" -InstallDns -Force
```

### DNS forwarder
On the DC, in **DNS Manager** → server **Properties → Forwarders**, add `10.0.0.2` (the VPC's `.2` resolver) so the DC can resolve external names while serving `soc.lab` internally.

---

## 3. Join Windows clients to the domain

Launch one or two more **Windows Server 2022** instances in `ad-subnet` (these act as endpoints). On each client, point DNS at the DC, then join:

```powershell
# point this client's DNS at the DC (adjust the interface alias to match)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 3" -ServerAddresses 10.0.30.83

# join the domain (prompts for SOC\Administrator credentials) and reboot
Add-Computer -DomainName "soc.lab" -Credential (Get-Credential) -Restart
```

> Find the right interface alias with `Get-NetAdapter`. After reboot you can log in as `SOC\Administrator`.

---

## Agents on AD hosts

Install the Wazuh agent + Sysmon on the DC and every client — see [03 — Wazuh](./03-wazuh.md) sections 4 and 5. The DC's domain-auth, logon, and Sysmon events are some of the richest detection material in the lab.

---

## Verification checklist

- [ ] DC reachable via RDP tunnel; promoted to `soc.lab` (NetBIOS `SOC`).
- [ ] DNS forwarder `10.0.0.2` set; DC resolves external names.
- [ ] Each client shows domain-joined; you can log in as `SOC\Administrator`.
- [ ] Wazuh shows the DC + clients as Active agents with Sysmon flowing.
