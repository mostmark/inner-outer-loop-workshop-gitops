#!/bin/bash
#
# Prints the resource footprint of the workshop: CPU/memory requests, limits and current usage of
# the running pods, per participant (my-project-, cn-project-, devspaces-<user>) and for the shared
# platform namespaces. Used for the sizing guidance in the README. Run as cluster-admin.
#
# Usage: ./footprint.sh [user ...]   (default: every user with a devspaces-<user> namespace)

set -uo pipefail

users="$*"
[[ -n "$users" ]] || users=$(oc get namespaces -o name | sed -n 's#^namespace/devspaces-##p')

# sum <namespaces...>: "cpu_req_m mem_req_Mi cpu_lim_m mem_lim_Mi cpu_use_m mem_use_Mi pods"
sum() {
  local ns_list="$*"
  {
    for ns in $ns_list; do
      oc get pods -n "$ns" --field-selector=status.phase=Running -o json 2>/dev/null
    done
  } | python3 -c '
import json, sys
def cpu(v):
    if not v: return 0
    return float(v[:-1]) if v.endswith("m") else float(v) * 1000
def mem(v):
    if not v: return 0
    units = {"Ki": 1/1024, "Mi": 1, "Gi": 1024, "Ti": 1024*1024, "K": 1/1000/1.048576, "M": 1/1.048576, "G": 1000/1.048576}
    for u, f in units.items():
        if v.endswith(u): return float(v[:-len(u)]) * f
    return float(v) / 1024 / 1024
dec = json.JSONDecoder(); data = sys.stdin.read(); i = 0; t = [0.0] * 4; pods = 0
while i < len(data):
    while i < len(data) and data[i].isspace(): i += 1
    if i >= len(data): break
    obj, i = dec.raw_decode(data, i)
    for p in obj.get("items", []):
        pods += 1
        for c in p["spec"].get("containers", []):
            r = c.get("resources", {})
            t[0] += cpu(r.get("requests", {}).get("cpu")); t[1] += mem(r.get("requests", {}).get("memory"))
            t[2] += cpu(r.get("limits", {}).get("cpu")); t[3] += mem(r.get("limits", {}).get("memory"))
print(" ".join("%d" % x for x in t), pods)'
}
usage() {
  local cpu=0 mem=0 c m
  for ns in "$@"; do
    while read -r c m; do
      cpu=$((cpu + ${c%m})); mem=$((mem + ${m%Mi}))
    done < <(oc adm top pods -n "$ns" --no-headers 2>/dev/null | awk '{print $2, $3}')
  done
  echo "$cpu $mem"
}

printf '%-28s %6s %9s %10s %9s %10s %9s %10s\n' "Scope" "Pods" "CPU req" "Mem req" "CPU lim" "Mem lim" "CPU use" "Mem use"
row() {
  local label="$1"; shift
  read -r creq mreq clim mlim pods <<<"$(sum "$@")"
  read -r cuse muse <<<"$(usage "$@")"
  printf '%-28s %6s %8sm %8sMi %8sm %8sMi %8sm %8sMi\n' "$label" "$pods" "$creq" "$mreq" "$clim" "$mlim" "$cuse" "$muse"
}
for u in $users; do
  row "$u (all)" "my-project-$u" "cn-project-$u" "devspaces-$u"
  row "  devspaces-$u" "devspaces-$u"
  row "  my-project-$u" "my-project-$u"
  row "  cn-project-$u" "cn-project-$u"
done
row "shared platform" openshift-devspaces istio-system istio-cni argocd gitea nexus lab-guide \
  kiali-operator gitea-operator openshift-pipelines openshift-gitops openshift-user-workload-monitoring
row "operators (openshift-operators)" openshift-operators openshift-gitops-operator
