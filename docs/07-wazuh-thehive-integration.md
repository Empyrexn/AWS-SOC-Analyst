# 07 — Wazuh → TheHive Integration

Automatically turns Wazuh alerts above a level threshold into TheHive alerts, attaching observables (source IP, agent IP) where present. This is the "SOAR-lite" glue that makes the lab a pipeline rather than a pile of tools.

Runs on the **Wazuh manager** (`10.0.10.125`, SSH `wazuh-user`) and posts to **TheHive at `10.0.10.29:9000`**.

> **Critical version note:** TheHive 5 needs **thehive4py v2.x** (this build used 2.0.3). The widely-copied integration scripts target thehive4py **v1** and will silently fail against TheHive 5. Use the v2 API: `from thehive4py import TheHiveApi`, build the alert as a dict, call `api.alert.create(alert=body)`.

---

## 1. Create a TheHive service user + API key

In TheHive (logged in as an **org** user/admin), create a **service account** with alert-creation permission and generate its **API key**. This is a **TheHive** key — distinct from the Cortex key in [06](./06-thehive-cortex.md). Treat it as a secret.

Confirm the manager can reach TheHive:
```bash
curl -s http://10.0.10.29:9000/api/status
```

---

## 2. The integration script

thehive4py v2 is already bundled under `/var/ossec/framework/python` on a current Wazuh manager. (Your login user may not be able to exec the bundled python directly without sudo — harmless; the integrator runs as the `wazuh` service user.)

Create `/var/ossec/integrations/custom-w2thive.py` (thehive4py v2):

```python
#!/usr/bin/env python3
import sys, json
from thehive4py import TheHiveApi
from thehive4py.types.alert import InputAlert

# args from Wazuh: <path-to-alert-json> <api_key> <hook_url>
alert_file = sys.argv[1]
api_key    = sys.argv[2]
hook_url   = sys.argv[3]

lvl_threshold = 7   # only forward Wazuh alerts at/above this level

with open(alert_file) as f:
    alert = json.load(f)

rule = alert.get("rule", {})
if int(rule.get("level", 0)) < lvl_threshold:
    sys.exit(0)

agent = alert.get("agent", {})
data  = alert.get("data", {})

observables = []
if data.get("srcip"):
    observables.append({"dataType": "ip", "data": data["srcip"], "message": "source IP"})
if agent.get("ip"):
    observables.append({"dataType": "ip", "data": agent["ip"], "message": "agent IP"})

body: InputAlert = {
    "type": "wazuh_alert",
    "source": "wazuh",
    "sourceRef": alert.get("id", "n/a"),
    "title": rule.get("description", "Wazuh alert"),
    "description": json.dumps(rule, indent=2),
    "severity": 2,
    "tags": ["wazuh", f"level:{rule.get('level')}"] + rule.get("groups", []),
    "observables": observables,
}

api = TheHiveApi(url=hook_url, apikey=api_key)
api.alert.create(alert=body)
```

Create the wrapper `/var/ossec/integrations/custom-w2thive` (Wazuh calls the wrapper, which calls the `.py`):
```sh
#!/bin/sh
WPYTHON_BIN="framework/python/bin/python3"
SCRIPT_PATH_NAME="$0"
DIR_NAME="$(cd $(dirname ${SCRIPT_PATH_NAME}); pwd -P)"
WAZUH_PATH="$(cd ${DIR_NAME}/..; pwd -P)"
PYTHON_SCRIPT="${DIR_NAME}/$(basename ${SCRIPT_PATH_NAME}).py"
"${WAZUH_PATH}/${WPYTHON_BIN}" "${PYTHON_SCRIPT}" "$@"
```

Set ownership/permissions on **both** files:
```bash
sudo chmod 750 /var/ossec/integrations/custom-w2thive /var/ossec/integrations/custom-w2thive.py
sudo chown root:wazuh /var/ossec/integrations/custom-w2thive /var/ossec/integrations/custom-w2thive.py
```

---

## 3. Register the integration in ossec.conf

Add this **inside** `<ossec_config>` in `/var/ossec/etc/ossec.conf` on the manager (outside the tag = "Invalid element" and the manager won't start):

```xml
<integration>
  <name>custom-w2thive</name>
  <hook_url>http://10.0.10.29:9000</hook_url>
  <api_key>THEHIVE_SERVICE_USER_API_KEY</api_key>
  <alert_format>json</alert_format>
</integration>
```
`hook_url` is TheHive on **:9000** (the host-published app port). Then restart and watch the log:
```bash
sudo systemctl restart wazuh-manager
sudo tail -f /var/ossec/logs/integrations.log
```
A successful run logs something like `TheHive alert created: ~33000`.

---

## Notes & gotchas

- **Observables only attach** when the Wazuh alert actually contains `data.srcip` and/or `agent.ip`. Many rule types don't populate `data.srcip`, so some alerts arrive with no observables — that's expected.
- View created alerts in TheHive **as an org user** (the platform admin has no Alerts tab — see [06](./06-thehive-cortex.md)).
- From an alert, an analyst promotes to a **case** and runs the IPs through **Cortex** analyzers.

---

## Verification checklist

- [ ] `curl http://10.0.10.29:9000/api/status` from the manager succeeds.
- [ ] `integrations.log` shows "TheHive alert created" after a level≥7 event.
- [ ] The alert appears in TheHive under an org user, with observables when the source alert had an IP.
- [ ] The TheHive service-user key is stored as a secret (rotate if it leaked).
