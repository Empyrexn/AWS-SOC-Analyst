# 06 — TheHive + Cortex

Case management (TheHive 5.7.1) and automated observable enrichment (Cortex 4.0.1), both as Docker stacks on a shared secops host. TheHive receives auto-alerts from Wazuh ([07](./07-wazuh-thehive-integration.md)) and dispatches observables to Cortex analyzers.

This build: host **10.0.10.29** (Ubuntu, user `ubuntu`). Profile dirs `~/thehive-stack/prod1-thehive` and `~/thehive-stack/prod1-cortex`.

> The Docker socket on this host often needs `sudo` — prefix docker/compose commands with `sudo` if you hit permission errors.

---

## 1. Host prep

Launch Ubuntu `t3.xlarge` (TheHive + Cortex + two Elasticsearch + Cassandra is RAM-hungry) in `secops-subnet`, SG `sg-secops`, no public IP. Install Docker (see [02](./02-vulnerable-targets-and-kali.md)). Then set the kernel param Elasticsearch needs:
```bash
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-thehive.conf
```

---

## 2. Deploy the StrangeBee stacks

Clone the official StrangeBee docker repo and use the prebuilt **prod1** profiles (each profile auto-configures all services — Cassandra, Elasticsearch, the app, and an Nginx HTTPS reverse proxy):
```bash
git clone https://github.com/StrangeBeeCorp/docker.git ~/thehive-stack
```

For **each** of TheHive and Cortex, go into its profile dir and run the init script, which generates `secret.conf`, `index.conf`, `.env`, self-signed certs, and a random Elasticsearch password:
```bash
cd ~/thehive-stack/prod1-thehive
bash ./scripts/init.sh        # prompts for a server name for the cert
docker compose up -d
docker compose ps             # all services running
```
Repeat for `~/thehive-stack/prod1-cortex`.

Resulting containers: `thehive` (9000), its `nginx` (443), `cortex` (9001), `cortex-nginx` (9443→443), plus each app's `elasticsearch` and TheHive's `cassandra`.

### ES out-of-memory (exit 137)
Elasticsearch containers were killed (exit 137 / OOM) on first boot. **Fix:** reduce the ES JVM heaps in the compose files (e.g. set `-Xms`/`-Xmx` lower to fit the host), then `docker compose up -d` again. The `vm.max_map_count` setting above is also required.

---

## 3. Access the UIs
```bash
ssh -i SOC-Analyst-Bastion-Key.pem \
  -L 7443:10.0.10.29:443 \    # TheHive -> https://localhost:7443
  -L 9443:10.0.10.29:9443 \   # Cortex  -> https://localhost:9443
  ec2-user@<bastion-public-ip>
```

---

## 4. Cortex first-run setup

1. Log into Cortex (`https://localhost:9443`) and create the superadmin.
2. Create an **organization** (this build: `soc-analyst-lab`).
3. Create an **org-admin** user in that org (this build: `SocAdmin`). **Analyzers are only visible/manageable to an org-admin — not the superadmin.**
4. Enable analyzers. The free no-API-key IP analyzers used here: **IP-API**, **TorProject**, **DShield**, **Abuse_Finder**. When enabling, set **Max TLP/PAP to AMBER (or RED)** or they won't run on AMBER observables. (Internal IPs correctly come back as "private range"/not found.)
5. Generate an **org-admin API key** (you'll give this to TheHive in step 6). Treat it as a secret.

### Cortex analyzer job-dir permission fix (AccessDenied)
Dockerized analyzers failed with `java.nio.file.AccessDeniedException` on `/tmp/cortex-jobs/...` — Cortex runs non-root and couldn't create the per-job folder in the bind-mounted directory. **Fix:**
```bash
sudo chmod -R 1777 ~/thehive-stack/prod1-cortex/cortex/cortex-jobs
```
Confirm the compose env `docker_job_directory` is the **absolute host path** (`/home/ubuntu/thehive-stack/prod1-cortex/cortex/cortex-jobs`), and that the Cortex service mounts both `/var/run/docker.sock` and `./cortex/cortex-jobs:/tmp/cortex-jobs` (the prod1 profile already does).

---

## 5. The Docker-network collision (why TheHive reaches Cortex by host IP)

**Do NOT `docker network connect` TheHive to Cortex's network.** Cortex's Elasticsearch service is aliased `elasticsearch` on that network — the same alias TheHive uses for its **own** ES. Joining the networks makes TheHive resolve `elasticsearch` to Cortex's ES (wrong credentials) → **401 Unauthorized** → TheHive won't boot.

**Fix:** reach Cortex over the **host IP + published port**. Add a published port to the Cortex service and bring it up:
```yaml
# in the cortex service of prod1-cortex/docker-compose.yml
    ports:
      - "9001:9001"
```
```bash
cd ~/thehive-stack/prod1-cortex && sudo docker compose up -d cortex
```
TheHive then talks to Cortex at **`http://10.0.10.29:9001`**. (If you previously joined the networks, `docker network disconnect` first.)

---

## 6. Wire TheHive → Cortex

Edit `~/thehive-stack/prod1-thehive/thehive/config/application.conf`. It should **end** with the Cortex module enable + a single `cortex` block (remove any duplicate `scalligraph.modules` lines and **do not** enable the MISP module — MISP without config breaks startup):

```hocon
play.modules.enabled += org.thp.thehive.connector.cortex.CortexModule

cortex {
  servers = [
    {
      name = "local-cortex"
      url  = "http://10.0.10.29:9001"
      auth { type = "bearer", key = "<CORTEX_ORG_ADMIN_API_KEY>" }
    }
  ]
  refreshDelay   = 1 minute
  maxRetryOnError = 3
}
```
Restart TheHive: `cd ~/thehive-stack/prod1-thehive && sudo docker compose restart thehive`.

You can also/instead configure this in TheHive UI → **Platform Management → Connectors → Cortex** (server URL `http://10.0.10.29:9001`, the key, **Proxy Disabled**; SSL settings are irrelevant over http).

### TheHive UI gotcha
The platform admin (`admin@thehive.local`) has **no Alerts/Cases tabs** — you must log in as an **org user** to see Alerts/Cases. Create an org and an org user for day-to-day work.

---

## Verification checklist

- [ ] `docker compose ps` shows all services up for both stacks (no ES 137 loops).
- [ ] Cortex analyzers visible under the **org-admin** account; a test run on a public IP returns **Success**.
- [ ] TheHive connector to Cortex shows healthy (no 401 at boot).
- [ ] Running an analyzer from a TheHive case observable returns a report.
- [ ] Rotate any API key that was pasted in plaintext during setup.
