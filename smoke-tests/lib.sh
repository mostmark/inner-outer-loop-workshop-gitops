#!/bin/bash
# Shared helpers for the smoke tests. Source it; do not run it.

PASSED=0
FAILED=0
FAILED_CHECKS=()

section() { echo; echo "=== $* ==="; }

# check <description> <command...>: runs the command quietly and prints PASS/FAIL.
check() {
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $description"; PASSED=$((PASSED + 1))
  else
    echo "FAIL  $description"; FAILED=$((FAILED + 1)); FAILED_CHECKS+=("$description")
  fi
}

# check_http <description> <url> <expected codes (space separated)>
check_http() {
  local description="$1" url="$2" expected="$3" code
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "$url")
  if [[ " $expected " == *" $code "* ]]; then
    echo "PASS  $description ($url -> $code)"; PASSED=$((PASSED + 1))
  else
    echo "FAIL  $description ($url -> $code, expected $expected)"; FAILED=$((FAILED + 1)); FAILED_CHECKS+=("$description")
  fi
}

summary() {
  echo
  echo "=== Summary: ${PASSED} passed, ${FAILED} failed ==="
  for c in "${FAILED_CHECKS[@]+"${FAILED_CHECKS[@]}"}"; do echo "  failed: $c"; done
  exit "$FAILED"
}

require_admin() {
  oc whoami >/dev/null 2>&1 || { echo "Error: not logged in to OpenShift." >&2; exit 1; }
  [[ "$(oc auth can-i '*' '*' --all-namespaces)" == "yes" ]] || { echo "Error: cluster-admin permissions are required." >&2; exit 1; }
}

# Users: from --users/--prefix/--names, else from the root Application's Helm parameters.
parse_user_args() {
  local count="" prefix="" names=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --users) count="$2"; shift 2 ;;
      --prefix) prefix="$2"; shift 2 ;;
      --names) names="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$count$prefix$names" ]]; then
    local p='{.spec.source.helm.parameters[?(@.name=="%s")].value}'
    count=$(oc get application inner-outer-loop-workshop -n openshift-gitops -o jsonpath="$(printf "$p" users.count)" 2>/dev/null)
    prefix=$(oc get application inner-outer-loop-workshop -n openshift-gitops -o jsonpath="$(printf "$p" users.prefix)" 2>/dev/null)
    names=$(oc get application inner-outer-loop-workshop -n openshift-gitops -o jsonpath="$(printf "$p" users.explicitNames)" 2>/dev/null)
    [[ "$names" == "null" ]] && names=""
    names=$(echo "$names" | tr -d '{}')
  fi
  if [[ -n "$names" ]]; then
    USERS=$(echo "$names" | tr ',' ' ')
  else
    USERS=$(for i in $(seq 1 "${count:-10}"); do printf '%s%s ' "${prefix:-user}" "$i"; done)
  fi
  export USERS
}

apps_domain() { oc get ingresses.config cluster -o jsonpath='{.spec.domain}'; }
api_server() { oc whoami --show-server; }

deployment_available() {
  local available
  available=$(oc get deployment "$2" -n "$1" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  [[ -n "$available" && "$available" -gt 0 ]]
}

# in_cluster_http <http://service.namespace.svc:port/path> <expected code>: request a cluster
# service through the API server's service proxy (no helper pod needed; needs cluster-admin).
in_cluster_http() {
  local url="$1" hostport path svc ns port
  hostport=$(echo "$url" | sed -E 's#^https?://([^/]+).*#\1#')
  path=$(echo "$url" | sed -E 's#^https?://[^/]+##')
  svc=${hostport%%.*}; ns=$(echo "$hostport" | cut -d. -f2); port=${hostport##*:}
  oc get --raw "/api/v1/namespaces/${ns}/services/http:${svc}:${port}/proxy${path}" >/dev/null
}

# can_i_as <user> <verb> <resource> <namespace>
can_i_as() { [[ "$(oc auth can-i "$2" "$3" -n "$4" --as "$1" 2>/dev/null)" == "yes" ]]; }
cannot_as() { [[ "$(oc auth can-i "$2" "$3" -n "$4" --as "$1" 2>/dev/null)" == "no" ]]; }
