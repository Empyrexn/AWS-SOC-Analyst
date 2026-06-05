# Configuration Files

Sanitized, copy-pasteable artifacts from the lab build. Each maps to a step in the [docs/](../docs/). **All secrets are placeholders** (`REPLACE_WITH_...`) — fill them in locally and never commit real keys. IPs are this build's private addresses (`10.0.x.x`); substitute your own.

```
configs/
├── docker/
│   └── run-vulnerable-targets.sh              # DVWA/Juice/WebGoat + Metasploitable2 (-dit)
├── wazuh/
│   ├── install-linux-agent.sh                 # agent install w/ WAZUH_MANAGER baked in
│   ├── install-windows-agent.ps1              # MSI install + Sysmon (SwiftOnSecurity)
│   ├── agent-docker-localfile-block.xml       # vuln host: collect container logs
│   ├── manager-ossec-integration-block.xml    # manager: <integration> -> TheHive
│   ├── custom-w2thive.py                       # Wazuh->TheHive script (thehive4py v2)
│   └── custom-w2thive                          # wrapper the manager invokes
├── thehive/
│   └── application.conf.cortex-connector.snippet
├── cortex/
│   └── docker-compose.cortex-ports.snippet.yml
├── security-onion/
│   ├── clean-install-prep.sh                   # cron-before-so-setup fix
│   └── verify-traffic-mirror.sh               # tcpdump on ens6 + VXLAN fallback
├── active-directory/
│   ├── promote-dc.ps1
│   └── join-domain.ps1
└── caldera/
    └── prep-windows-endpoint.ps1              # disable Tamper/RT protection for Sandcat
```

## Where each file goes

| File | Destination on host |
|---|---|
| `wazuh/agent-docker-localfile-block.xml` | inside `<ossec_config>` in `/var/ossec/etc/ossec.conf` (vuln host) |
| `wazuh/manager-ossec-integration-block.xml` | inside `<ossec_config>` in `/var/ossec/etc/ossec.conf` (manager) |
| `wazuh/custom-w2thive.py` | `/var/ossec/integrations/custom-w2thive.py` (manager) |
| `wazuh/custom-w2thive` | `/var/ossec/integrations/custom-w2thive` (manager) |
| `thehive/application.conf.cortex-connector.snippet` | append to `~/thehive-stack/prod1-thehive/thehive/config/application.conf` |
| `cortex/docker-compose.cortex-ports.snippet.yml` | merge into `~/thehive-stack/prod1-cortex/docker-compose.yml` |

## Permissions reminder

The Wazuh integration files need:
```bash
sudo chmod 750 /var/ossec/integrations/custom-w2thive /var/ossec/integrations/custom-w2thive.py
sudo chown root:wazuh /var/ossec/integrations/custom-w2thive /var/ossec/integrations/custom-w2thive.py
```

## Before committing to GitHub

- Replace nothing back to real values in these files — keep placeholders in the repo.
- Double-check you haven't pasted a real API key, password, or the bastion's public IP anywhere.
- Rotate any key that was ever live during the build.
