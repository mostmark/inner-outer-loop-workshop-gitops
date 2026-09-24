#!/bin/bash
#
# Switches the part of the workshop the lab guide shows, for example between the two days of a
# two-day event:
#
#   ./set-guide-part.sh inner   # day 1: Part 1 Inner Loop only
#   ./set-guide-part.sh outer   # day 2: Part 2 Outer Loop only
#   ./set-guide-part.sh all     # both parts
#
# It sets the guidePart Helm parameter of the root Application; Argo CD then restarts the lab
# guide pod with the other variant (about a minute). Participants keep their URLs, and nothing
# else in the workshop changes.

set -euo pipefail

GITOPS_NAMESPACE=openshift-gitops
ROOT_APP=inner-outer-loop-workshop
PART="${1:-}"

[[ "$PART" =~ ^(all|inner|outer)$ ]] || { sed -n '3,12p' "$0"; exit 1; }
command -v oc >/dev/null 2>&1 || { echo "Error: 'oc' CLI not found." >&2; exit 1; }
oc get application "$ROOT_APP" -n "$GITOPS_NAMESPACE" >/dev/null 2>&1 \
  || { echo "Error: Application $ROOT_APP not found in $GITOPS_NAMESPACE. Is the workshop installed?" >&2; exit 1; }

# Update the guidePart parameter (or add it), keeping every other parameter.
params=$(oc get application "$ROOT_APP" -n "$GITOPS_NAMESPACE" -o json | python3 -c '
import json, sys
part = sys.argv[1]
params = json.load(sys.stdin)["spec"]["source"]["helm"].get("parameters", [])
params = [p for p in params if p["name"] != "guidePart"] + [{"name": "guidePart", "value": part}]
print(json.dumps(params))' "$PART")
oc patch application "$ROOT_APP" -n "$GITOPS_NAMESPACE" --type merge \
  -p "{\"spec\":{\"source\":{\"helm\":{\"parameters\":${params}}}}}" >/dev/null
echo "Lab guide part set to '${PART}'. Waiting for the lab guide to roll out..."

deadline=$((SECONDS + 300))
until [[ "$(oc get deployment lab-guide -n lab-guide -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WORKSHOP_PART")].value}' 2>/dev/null)" == "$PART" ]]; do
  [[ $SECONDS -ge $deadline ]] && { echo "Error: Argo CD did not apply the change within 5 minutes." >&2; exit 1; }
  sleep 5
done
oc rollout status deployment/lab-guide -n lab-guide --timeout=300s
echo "Done. The lab guide now shows: $(case "$PART" in all) echo "Part 1 and Part 2";; inner) echo "Part 1 (Inner Loop) only";; outer) echo "Part 2 (Outer Loop) only";; esac)."
