#!/usr/bin/env bash
# Vulnerable target containers for the SOC lab — run on the Ubuntu host in vuln-subnet.
# See docs/02-vulnerable-targets-and-kali.md
set -euo pipefail

# Web apps
docker run -d  --name dvwa    -p 8081:80   vulnerables/web-dvwa
docker run -d  --name juice   -p 8082:3000 bkimminich/juice-shop
docker run -d  --name webgoat -p 8083:8080 webgoat/webgoat

# Metasploitable2 — MUST be -dit (not -d): its CMD is `sh -c '/bin/services.sh && bash'`,
# and the trailing bash exits instantly without a TTY, stopping the container.
# SSH is mapped 2222:22 because the host's own sshd already owns 22.
docker run -dit --name metasploitable2 \
  -p 21:21 -p 23:23 -p 25:25 -p 80:80 \
  -p 139:139 -p 445:445 -p 3306:3306 -p 5432:5432 \
  -p 6667:6667 -p 8180:8180 -p 1524:1524 \
  -p 2222:22 \
  tleemcjr/metasploitable2

# Persist across instance stop/start
docker update --restart=unless-stopped "$(docker ps -aq)"

echo "Done. Verify: docker ps ; curl http://localhost:80"
