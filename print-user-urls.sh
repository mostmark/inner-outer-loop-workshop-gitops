#!/bin/bash
#
# Prints the ready-to-use lab guide URL of every workshop participant, so the instructor can hand
# them out. The users are read from the root Application (the same parameters bootstrap.sh set)
# unless --users/--prefix/--names are given.
#
# Usage: ./print-user-urls.sh [--users N] [--prefix P] [--names a,b] [--credentials-file FILE] [--csv]
#
# Passwords come from (in this order) --credentials-file / WORKSHOP_CREDENTIALS_FILE, the cluster
# Secret that bootstrap.sh created (needs cluster-admin), or WORKSHOP_USER_PASSWORD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/credentials.sh
source "${SCRIPT_DIR}/lib/credentials.sh"

GITOPS_NAMESPACE=openshift-gitops
ROOT_APP=inner-outer-loop-workshop
USERS_COUNT=""
USERS_PREFIX=""
USERS_EXPLICIT_NAMES=""
FORMAT=text

while [[ $# -gt 0 ]]; do
  case "$1" in
    --users) USERS_COUNT="$2"; shift 2 ;;
    --prefix) USERS_PREFIX="$2"; shift 2 ;;
    --names) USERS_EXPLICIT_NAMES="$2"; shift 2 ;;
    --csv) FORMAT=csv; shift ;;
    --credentials-file) WORKSHOP_CREDENTIALS_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v oc >/dev/null 2>&1 || { echo "Error: 'oc' CLI not found." >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "Error: not logged in to OpenShift." >&2; exit 1; }
creds_check_source || exit 1

# Users from the root Application's Helm parameters, unless given on the command line.
param() {
  oc get application "$ROOT_APP" -n "$GITOPS_NAMESPACE" \
    -o jsonpath="{.spec.source.helm.parameters[?(@.name==\"$1\")].value}" 2>/dev/null || true
}
if [[ -z "$USERS_COUNT$USERS_PREFIX$USERS_EXPLICIT_NAMES" ]]; then
  USERS_COUNT=$(param users.count)
  USERS_PREFIX=$(param users.prefix)
  names=$(param users.explicitNames)
  [[ "$names" != "null" ]] && USERS_EXPLICIT_NAMES=$(echo "$names" | tr -d '{}')
fi
if [[ -n "$USERS_EXPLICIT_NAMES" ]]; then
  USERS=$(echo "$USERS_EXPLICIT_NAMES" | tr ',' ' ')
else
  USERS_COUNT=${USERS_COUNT:-10}
  USERS_PREFIX=${USERS_PREFIX:-user}
  USERS=$(for i in $(seq 1 "$USERS_COUNT"); do printf '%s%s ' "$USERS_PREFIX" "$i"; done)
fi

LAB_GUIDE_HOST=$(oc get route doc -n lab-guide -o jsonpath='{.spec.host}' 2>/dev/null || true)
[[ -n "$LAB_GUIDE_HOST" ]] || { echo "Error: lab guide route doc in namespace lab-guide not found. Is the workshop installed?" >&2; exit 1; }
CONSOLE_HOST=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}')
API_HOST=$(oc whoami --show-server | sed -E 's#^https?://##; s#/.*$##')

urlencode() {
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  echo "$out"
}
[[ "$FORMAT" == "csv" ]] && echo "username,lab_guide_url"
for user in $USERS; do
  password=$(user_password "$user") && [[ -n "$password" ]] \
    || { echo "Error: no password for $user (credentials file, cluster Secret or WORKSHOP_USER_PASSWORD)." >&2; exit 1; }
  PASSWORD=$(urlencode "$password")
  url="https://${LAB_GUIDE_HOST}?OPENSHIFT_USERNAME=$(urlencode "$user")&OPENSHIFT_PASSWORD=${PASSWORD}&OPENSHIFT_CONSOLE_URL=${CONSOLE_HOST}&OPENSHIFT_API_URL=${API_HOST}"
  if [[ "$FORMAT" == "csv" ]]; then
    echo "${user},${url}"
  else
    printf '%-12s %s\n' "$user" "$url"
  fi
done
