# 09 — Nessus (Vulnerability Management)

Authenticated and unauthenticated vulnerability scanning of the lab subnets with Nessus Essentials (free, up to 16 IPs). Web UI on **:8834**.

---

## 1. Install

On a secops box (Ubuntu/Amazon Linux, `t3.medium`+), download the Nessus package from Tenable and install:
```bash
# download the matching .deb/.rpm from tenable.com, then e.g.:
sudo dpkg -i Nessus-*.deb        # (or: sudo rpm -i Nessus-*.rpm)
sudo systemctl enable --now nessusd
```
Reach the UI via the bastion:
```bash
ssh -i SOC-Analyst-Bastion-Key.pem -L 8834:10.0.10.x:8834 ec2-user@<bastion-public-ip>
# browse https://localhost:8834
```
In the setup wizard, choose **Nessus Essentials**, register for the free activation code, create the admin user, and let it download plugins (takes a while).

---

## 2. Create a scan

**New Scan → Basic Network Scan.** Targets = the lab hosts you want (the vuln host `10.0.40.222`, the DC `10.0.30.83`, and the Windows clients). This scan is **read-only/safe** — no exploitation or DoS.

---

## 3. Credentialed scanning (Credentials tab)

Authenticated scans see far more than network-only scans.

**Windows category:** username `Administrator`, the password, and **Domain = `SOC`** (the NetBIOS name). One domain credential covers the DC **and** the clients because Domain Admins are local admins everywhere. Also tick **Start the Remote Registry service** and **Enable administrative shares** so Nessus can authenticate over SMB/WMI.

**SSH category** (for the Ubuntu vuln host): authentication = **public key**, username `ubuntu`, key = `SOC-Analyst-Bastion-Key.pem`, **Elevate privileges with = `sudo`** (leave sudo user blank → root; leave sudo password blank since `ubuntu` has passwordless sudo; binary location `/usr/bin`).

---

## 4. The Windows-clients-skipped gotcha (host discovery)

The two Windows **clients** initially never appeared in results. **Root cause was host discovery, not credentials:** the Windows firewall blocks ICMP, so Nessus marked the hosts dead and skipped them entirely (and the same firewall would have blocked credentialed SMB/WMI checks).

**Fix** — disable the host firewall on the clients:
```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
```
This restored both discovery and authenticated checks. It's safe here because the clients sit in a **private, security-group-gated subnet** with no internet exposure — the SGs remain the real perimeter. (Re-enable the firewall if you later want to practice scanning a more realistic, firewalled endpoint.)

After this, all four hosts scan and return authenticated findings.

---

## Verification checklist

- [ ] Nessus UI reachable via tunnel; Essentials activated; plugins downloaded.
- [ ] Basic Network Scan created with all target IPs.
- [ ] Windows creds use Domain `SOC`; Remote Registry + admin shares enabled.
- [ ] SSH creds use the key with sudo elevation for the vuln host.
- [ ] All four hosts appear in results (client firewall disabled) with credentialed (not just network) findings.
