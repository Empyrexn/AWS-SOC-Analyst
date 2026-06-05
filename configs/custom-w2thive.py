#!/usr/bin/env python3
"""
custom-w2thive.py — Wazuh -> TheHive integration (thehive4py v2.x / TheHive 5).
Install at /var/ossec/integrations/custom-w2thive.py on the Wazuh MANAGER.
Invoked by the wrapper `custom-w2thive` with: <alert-json-path> <api_key> <hook_url>

IMPORTANT: TheHive 5 requires thehive4py v2.x. v1-based scripts will fail.
See docs/07-wazuh-thehive-integration.md
"""
import sys
import json

from thehive4py import TheHiveApi
from thehive4py.types.alert import InputAlert

# --- args passed by Wazuh / the wrapper ---
alert_file = sys.argv[1]
api_key = sys.argv[2]
hook_url = sys.argv[3]

# Only forward Wazuh alerts at/above this rule level
LVL_THRESHOLD = 7

with open(alert_file) as f:
    alert = json.load(f)

rule = alert.get("rule", {})
if int(rule.get("level", 0)) < LVL_THRESHOLD:
    sys.exit(0)

agent = alert.get("agent", {})
data = alert.get("data", {})

# Observables only attach when the Wazuh alert actually carries an IP.
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
