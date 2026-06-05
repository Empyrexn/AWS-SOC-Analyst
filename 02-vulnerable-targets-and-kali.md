# 02 — Vulnerable Targets & Kali

Stands up the attack surface (vulnerable web apps + Metasploitable2 as Docker containers on one Ubuntu host) and the Kali attacker box. These generate the malicious telemetry the whole detection stack is built to catch.

**Design decision:** vulnerable targets run as **containers on a single Ubuntu host** (Route A), not as separate EC2 instances. Metasploitable/VulnHub ship as VM images, not AMIs; containers are far lower-friction and consolidate the diagram to one EC2 box in `vuln-subnet`.

---

## Part A — Ubuntu Docker host (vuln-subnet)

### Launch
EC2 → Launch:
- Name: `vuln-docker-host`
- AMI: **Ubuntu Server 24.04 LTS**
- Type: `t3.medium` (or `t3.large` for many containers)
- Subnet: `vuln-subnet` (10.0.40.0/24), **no public IP**
- SG: `sg-internal`
- Key: `SOC-Analyst-Bastion-Key`

This build's host landed at **10.0.40.222** (user `ubuntu`). Reach it via the bastion.

### Install Docker
```bash
sudo apt update && sudo apt -y install docker.io docker-compose-v2
sudo usermod -aG docker $USER && newgrp docker
```

### Run the vulnerable web apps
```bash
docker run -d --name dvwa    -p 8081:80   vulnerables/web-dvwa
docker run -d --name juice   -p 8082:3000 bkimminich/juice-shop
docker run -d --name webgoat -p 8083:8080 webgoat/webgoat
```

### Run Metasploitable2 — note the `-dit` gotcha
Metasploitable2's image CMD is `sh -c '/bin/services.sh && bash'`: it starts all services, then drops to `bash`. With plain `-d` (no TTY) that trailing `bash` exits immediately and **the container stops**. Use **`-dit`** so the pseudo-terminal keeps `bash` (and the container) alive:

```bash
docker run -dit --name metasploitable2 \
  -p 21:21 -p 23:23 -p 25:25 -p 80:80 \
  -p 139:139 -p 445:445 -p 3306:3306 -p 5432:5432 \
  -p 6667:6667 -p 8180:8180 -p 1524:1524 \
  -p 2222:22 \
  tleemcjr/metasploitable2
```

Port notes: each `-p HOST:CONTAINER` publishes the service on the **host's** private IP (`10.0.40.222`), so Kali targets `10.0.40.222` on these ports. **SSH is mapped `2222:22`** because the host's own sshd owns 22. Services exposed: 21 FTP (vsftpd backdoor), 23 telnet, 25 SMTP, 80 HTTP, 139/445 Samba, 3306 MySQL, 5432 Postgres, 6667 UnrealIRCd, 8180 Tomcat, 1524 ingreslock root bind shell, 2222 SSH.

Harmless log noise: `/dev/console: No such file or directory` lines are expected inside the container and don't affect services.

### Persistence across instance stop/start
Containers don't auto-start after the EC2 instance is stopped/started unless told to:
```bash
# restart everything once:
sudo docker start $(sudo docker ps -aq)
# make it automatic going forward:
sudo docker update --restart=unless-stopped $(sudo docker ps -aq)
```

### Verify
```bash
docker ps                 # all containers Up
curl http://localhost:80  # Metasploitable web root (ASCII banner)
curl http://localhost:8081 # DVWA
```

---

## Part B — Kali attacker (attack-subnet)

### Launch
- AMI: **Kali Linux** (official, AWS Marketplace — subscribe, free)
- Type: `t3.medium` minimum
- Subnet: `attack-subnet` (10.0.20.0/24), **no public IP**
- SG: `sg-internal`
- Key: `SOC-Analyst-Bastion-Key`, default user `kali`

### Set up tools
```bash
sudo apt update && sudo apt -y full-upgrade
sudo apt -y install kali-linux-default   # full toolset (optional, large)
```

### Confirm reachability to targets
```bash
nmap 10.0.40.222            # should light up FTP/SMB/MySQL/Tomcat/etc.
nmap -p 2222 10.0.40.222    # Metasploitable SSH on the remapped port
```
`sg-internal`'s "all traffic from 10.0.0.0/16" rule already permits Kali → targets, so no SG change is needed.

---

## Wazuh agent (both hosts)

Both the Ubuntu host and Kali get a Wazuh agent — covered in [03 — Wazuh](./03-wazuh.md). The vuln host also collects **Docker container logs** (config block is in the Wazuh doc).

---

## Verification checklist

- [ ] `docker ps` on the vuln host shows DVWA, Juice, WebGoat, **and** Metasploitable2 all `Up`.
- [ ] Containers survive an instance stop/start (restart policy set).
- [ ] From Kali, `nmap 10.0.40.222` enumerates the Metasploitable services.
- [ ] Kali can browse DVWA/Juice/WebGoat at `10.0.40.222:8081/8082/8083`.
