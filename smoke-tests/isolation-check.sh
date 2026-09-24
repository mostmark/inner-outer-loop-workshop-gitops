#!/bin/bash
#
# Confirms that one participant cannot see or modify another participant's namespaces, Argo CD
# Applications or Gitea repositories. Logs in as both users with their real credentials
# (WORKSHOP_USER_PASSWORD), not through impersonation.
#
# Usage: WORKSHOP_USER_PASSWORD=... ./isolation-check.sh <user-a> <user-b>   (default: user1 user2)
# Exit code: number of failed checks.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

A="${1:-user1}"
B="${2:-user2}"
[[ -n "${WORKSHOP_USER_PASSWORD:-}" ]] || { echo "Error: WORKSHOP_USER_PASSWORD is not set." >&2; exit 1; }
API=$(oc whoami --show-server 2>/dev/null)
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
[[ -n "$API" && -n "$DOMAIN" ]] || { echo "Error: log in to the cluster first." >&2; exit 1; }
GITEA="https://gitea-server-gitea.${DOMAIN}/api/v1"
ARGOCD="https://argocd-server-argocd.${DOMAIN}/api/v1"
KIALI="https://kiali-istio-system.${DOMAIN}/api"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

as() { KUBECONFIG="${WORK}/$1" oc "${@:2}"; }  # as <user> <oc args...>
login() { KUBECONFIG="${WORK}/$1" oc login "$API" -u "$1" -p "$WORKSHOP_USER_PASSWORD" --insecure-skip-tls-verify=true >/dev/null 2>&1; }
denied() { ! "$@" >/dev/null 2>&1; }
code() { curl -sk -o /dev/null -w '%{http_code}' --max-time 20 -H 'Content-Type: application/json' "$@"; }
gitea_code() { local u="$1"; shift; code -u "${u}:${WORKSHOP_USER_PASSWORD}" "$@"; }

section "Log in"
check "Log in as $A" login "$A"
check "Log in as $B" login "$B"

section "OpenShift: $A vs namespaces of $B"
check "$A sees only their own projects" bash -c \
  "[ -z \"\$(KUBECONFIG=${WORK}/$A oc get projects -o name | grep -v -E 'project.openshift.io/(my-project|cn-project|devspaces)-$A\$')\" ]"
check "$A cannot list namespaces cluster-wide" denied as "$A" get namespaces
for ns in "my-project-$B" "cn-project-$B" "devspaces-$B"; do
  check "$A cannot list pods in $ns" denied as "$A" get pods -n "$ns"
  check "$A cannot read secrets in $ns" denied as "$A" get secrets -n "$ns"
  check "$A cannot create a ConfigMap in $ns" denied as "$A" create configmap isolation-probe -n "$ns" --from-literal=a=b
  check "$A cannot delete the namespace $ns" denied as "$A" delete namespace "$ns" --dry-run=server
done
check "$A cannot exec into $B's workspace" bash -c \
  "[ \"\$(KUBECONFIG=${WORK}/$A oc auth can-i create pods/exec -n devspaces-$B)\" = no ]"
check "$A cannot read the Argo CD admin secret" denied as "$A" get secret argocd-cluster -n argocd
check "$A cannot read the Gitea bootstrap secrets" denied as "$A" get secret workshop-user-password -n gitea
check "$A cannot change the mesh control plane" denied as "$A" patch istio default --type merge -p '{"metadata":{"labels":{"probe":"x"}}}'

section "Argo CD (participant instance): $A vs $B"
TOKEN_A=$(as "$A" get secret argocd-env-secret -n "cn-project-$A" -o jsonpath='{.data.ARGOCD_AUTH_TOKEN}' 2>/dev/null | base64 -d)
TOKEN_B=$(as "$B" get secret argocd-env-secret -n "cn-project-$B" -o jsonpath='{.data.ARGOCD_AUTH_TOKEN}' 2>/dev/null | base64 -d)
check "$A can read their own Argo CD token" test -n "$TOKEN_A"
check "$A cannot read $B's Argo CD token" denied as "$A" get secret argocd-env-secret -n "cn-project-$B"
probe_app() { # probe_app <name> <project> <namespace>
  printf '{"metadata":{"name":"%s","namespace":"argocd"},"spec":{"project":"%s","source":{"repoURL":"http://gitea-server.gitea.svc:3000/%s/isolation-probe.git","path":".","targetRevision":"HEAD"},"destination":{"server":"https://kubernetes.default.svc","namespace":"%s"}}}' \
    "$1" "$2" "${4:-$A}" "$3"
}
check "$A can create an Application in their own project" test "$(code -X POST -H "Authorization: Bearer $TOKEN_A" \
  -d "$(probe_app "isolation-probe-$A" "cn-project-$A" "cn-project-$A")" "$ARGOCD/applications?validate=false")" = 200
check "$B can create an Application in their own project" test "$(code -X POST -H "Authorization: Bearer $TOKEN_B" \
  -d "$(probe_app "isolation-probe-$B" "cn-project-$B" "cn-project-$B" "$B")" "$ARGOCD/applications?validate=false")" = 200
check "$A cannot see $B's Application" test "$(code -H "Authorization: Bearer $TOKEN_A" "$ARGOCD/applications/isolation-probe-$B")" = 403
check "$A's Application list has no $B project" bash -c \
  "! curl -sk -H 'Authorization: Bearer $TOKEN_A' '$ARGOCD/applications' | grep -q 'cn-project-$B'"
check "$A cannot create an Application in $B's project" test "$(code -X POST -H "Authorization: Bearer $TOKEN_A" \
  -d "$(probe_app "isolation-probe-x" "cn-project-$B" "cn-project-$B")" "$ARGOCD/applications?validate=false")" = 403
check "$A's project cannot deploy into $B's namespace" bash -c "[ \"\$(curl -sk -o /dev/null -w '%{http_code}' -X POST \
  -H 'Authorization: Bearer $TOKEN_A' -d '$(probe_app "isolation-probe-y" "cn-project-$A" "cn-project-$B")' \
  '$ARGOCD/applications?validate=false')\" != 200 ]"
check "$A cannot sync $B's Application" test "$(code -X POST -H "Authorization: Bearer $TOKEN_A" -d '{}' \
  "$ARGOCD/applications/isolation-probe-$B/sync")" = 403
check "$A cannot delete $B's Application" test "$(code -X DELETE -H "Authorization: Bearer $TOKEN_A" \
  "$ARGOCD/applications/isolation-probe-$B?cascade=false")" = 403
code -X DELETE -H "Authorization: Bearer $TOKEN_A" "$ARGOCD/applications/isolation-probe-$A?cascade=false" >/dev/null
code -X DELETE -H "Authorization: Bearer $TOKEN_B" "$ARGOCD/applications/isolation-probe-$B?cascade=false" >/dev/null

section "Gitea: $A vs repositories of $B"
gitea_code "$B" -X POST -H 'Content-Type: application/json' -d '{"name":"isolation-probe","auto_init":true}' "$GITEA/user/repos" >/dev/null
check "$B owns repository isolation-probe" test "$(gitea_code "$B" "$GITEA/repos/$B/isolation-probe")" = 200
check "$A cannot write to $B's repository" test "$(gitea_code "$A" -X POST -H 'Content-Type: application/json' \
  -d '{"content":"cHJvYmU=","message":"probe"}' "$GITEA/repos/$B/isolation-probe/contents/probe.txt")" != 201
check "$A cannot delete $B's repository" test "$(gitea_code "$A" -X DELETE "$GITEA/repos/$B/isolation-probe")" != 204
check "$A cannot change $B's repository settings" test "$(gitea_code "$A" -X PATCH -H 'Content-Type: application/json' \
  -d '{"private":true}' "$GITEA/repos/$B/isolation-probe")" != 200
check "$A cannot use the admin API" test "$(gitea_code "$A" "$GITEA/admin/users")" = 403
check "$A cannot push over git to $B's repository" bash -c \
  "cd $WORK && git init -q -b main push && cd push && git commit -q --allow-empty -m probe &&
   git -c http.sslVerify=false push 'https://$A:$(printf %s "$WORKSHOP_USER_PASSWORD" | jq -sRr @uri)@gitea-server-gitea.${DOMAIN}/$B/isolation-probe.git' main:refs/heads/probe 2>&1 |
   grep -q -i -E '403|denied|not allowed|permission'"
gitea_code "$B" -X DELETE "$GITEA/repos/$B/isolation-probe" >/dev/null

section "Kiali"
check "$A's Kiali view does not include $B's namespaces" bash -c \
  "! curl -sk -H 'Authorization: Bearer $(as "$A" whoami -t)' '$KIALI/namespaces' | grep -q -- '-$B\"'"

summary
