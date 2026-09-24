#!/bin/bash
#
# Bootstraps the Inner & Outer Loop workshop on an OpenShift cluster.
#
# This is the only imperative step. It:
#   1. installs the OpenShift GitOps operator (pinned channel) and waits for it,
#   2. gives the provisioning Argo CD instance (openshift-gitops) the permissions and the
#      Application health check the charts need,
#   3. creates the secrets that must not live in Git,
#   4. applies the root Application (app-of-apps) and waits until everything is Synced and Healthy,
#   5. prints the lab guide URL template.
#
# It is idempotent: running it again converges the cluster to the same state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/credentials.sh
source "${SCRIPT_DIR}/lib/credentials.sh"

# ---------------------------------------------------------------------------------------------
# Defaults (override with flags or environment variables)
# ---------------------------------------------------------------------------------------------
USERS_COUNT="${USERS_COUNT:-10}"
USERS_PREFIX="${USERS_PREFIX:-user}"
USERS_EXPLICIT_NAMES="${USERS_EXPLICIT_NAMES:-}"
REPO_URL="${REPO_URL:-https://github.com/mostmark/inner-outer-loop-workshop-gitops.git}"
REVISION="${REVISION:-main}"
GITOPS_CHANNEL="${GITOPS_CHANNEL:-gitops-1.21}"
GUIDE_PART="${GUIDE_PART:-all}"
WORKSHOP_CREDENTIALS_FILE="${WORKSHOP_CREDENTIALS_FILE:-}"
TIMEOUT="${TIMEOUT:-3600}"
WAIT=true

GITOPS_NAMESPACE=openshift-gitops
ROOT_APP=inner-outer-loop-workshop

usage() {
  cat <<EOF
Usage: WORKSHOP_USER_PASSWORD=<password> $0 [options]
       $0 --credentials-file <file> [options]

Options:
  --users N          Number of generated users <prefix>1..<prefix>N (default: ${USERS_COUNT})
  --prefix PREFIX    Prefix for generated user names (default: ${USERS_PREFIX})
  --names a,b,c      Explicit user names; when set, --users and --prefix are ignored
  --credentials-file FILE
                     Unique password per user: a file with one "username,password" per line
                     (see README, "User Passwords"). Without it, all users share
                     WORKSHOP_USER_PASSWORD.
  --guide-part PART  Lab guide content: all (Part 1 and Part 2), inner (Part 1 only) or
                     outer (Part 2 only) (default: ${GUIDE_PART}). Switch later with
                     set-guide-part.sh
  --repo URL         Git repository with this GitOps content (default: ${REPO_URL})
  --revision REV     Git revision to deploy (default: ${REVISION})
  --timeout SECONDS  How long to wait for everything to be Synced and Healthy (default: ${TIMEOUT})
  --no-wait          Apply the root Application and exit without waiting
  -h, --help         Show this help

Environment:
  WORKSHOP_USER_PASSWORD     Password shared by all pre-created workshop users (default mode).
  WORKSHOP_CREDENTIALS_FILE  Same as --credentials-file.
  One of the two is required. The passwords are used for the users' Gitea accounts, their
  workspaces and the lab guide URLs, and are stored only in the cluster.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --users) USERS_COUNT="$2"; shift 2 ;;
    --prefix) USERS_PREFIX="$2"; shift 2 ;;
    --names) USERS_EXPLICIT_NAMES="$2"; shift 2 ;;
    --guide-part) GUIDE_PART="$2"; shift 2 ;;
    --credentials-file) WORKSHOP_CREDENTIALS_FILE="$2"; shift 2 ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --revision) REVISION="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --no-wait) WAIT=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "Error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------------------------
command -v oc >/dev/null 2>&1 || die "'oc' CLI not found. Please install it first."
oc whoami >/dev/null 2>&1 || die "Not logged in to OpenShift. Please run 'oc login' first."
if [[ -z "$WORKSHOP_CREDENTIALS_FILE" && -z "${WORKSHOP_USER_PASSWORD:-}" ]]; then
  die "set WORKSHOP_USER_PASSWORD (shared password) or pass --credentials-file (one password per user)."
fi
[[ "$(oc auth can-i '*' '*' --all-namespaces)" == "yes" ]] || die "cluster-admin permissions are required."
if [[ -z "$USERS_EXPLICIT_NAMES" ]] && ! [[ "$USERS_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  die "--users must be a positive integer."
fi
[[ "$GUIDE_PART" =~ ^(all|inner|outer)$ ]] || die "--guide-part must be all, inner or outer."

# The configured users, and their passwords when a credentials file is used: every user must be in
# the file with a non-empty password, so that nobody silently gets a wrong or empty password.
if [[ -n "$USERS_EXPLICIT_NAMES" ]]; then
  CONFIGURED_USERS=$(echo "$USERS_EXPLICIT_NAMES" | tr ',' ' ')
else
  CONFIGURED_USERS=$(for i in $(seq 1 "$USERS_COUNT"); do printf '%s%s ' "$USERS_PREFIX" "$i"; done)
fi
if [[ -n "$WORKSHOP_CREDENTIALS_FILE" ]]; then
  [[ -r "$WORKSHOP_CREDENTIALS_FILE" ]] || die "credentials file '$WORKSHOP_CREDENTIALS_FILE' is not readable."
  missing=""
  for user in $CONFIGURED_USERS; do
    password=$(creds_file_password "$WORKSHOP_CREDENTIALS_FILE" "$user") && [[ -n "$password" ]] || missing="$missing $user"
  done
  [[ -z "$missing" ]] || die "no password in $WORKSHOP_CREDENTIALS_FILE for:$missing"
  unset password
  extra=$(creds_file_users "$WORKSHOP_CREDENTIALS_FILE" | while read -r user; do
    [[ " $CONFIGURED_USERS " == *" $user "* ]] || printf '%s ' "$user"; done)
fi

log "Logged in as: $(oc whoami)"
log "Server:       $(oc whoami --show-server)"
if [[ -n "$USERS_EXPLICIT_NAMES" ]]; then
  log "Users:        ${USERS_EXPLICIT_NAMES}"
else
  log "Users:        ${USERS_PREFIX}1..${USERS_PREFIX}${USERS_COUNT}"
fi
log "Source:       ${REPO_URL}@${REVISION}"
log "Lab guide:    ${GUIDE_PART} (all = Part 1 and Part 2, inner = Part 1 only, outer = Part 2 only)"
if [[ -n "$WORKSHOP_CREDENTIALS_FILE" ]]; then
  log "Passwords:    one per user, from ${WORKSHOP_CREDENTIALS_FILE}"
  if [[ -n "${WORKSHOP_USER_PASSWORD:-}" ]]; then log "              (WORKSHOP_USER_PASSWORD is set but not used)"; fi
  if [[ -n "$extra" ]]; then log "              (ignored, not configured users in the file: ${extra})"; fi
else
  log "Passwords:    shared (WORKSHOP_USER_PASSWORD)"
fi

wait_for() {
  # wait_for <description> <timeout-seconds> <command...>
  local description="$1" timeout="$2"; shift 2
  local deadline=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    [[ $SECONDS -ge $deadline ]] && die "Timed out waiting for ${description}."
    sleep 10
  done
  log "${description}: ready"
}

# ---------------------------------------------------------------------------------------------
# 1. OpenShift GitOps operator
# ---------------------------------------------------------------------------------------------
log "Installing the OpenShift GitOps operator (channel ${GITOPS_CHANNEL})"
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops-operator
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: ${GITOPS_CHANNEL}
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

gitops_csv_succeeded() {
  local csv
  csv=$(oc get subscriptions.operators.coreos.com openshift-gitops-operator -n openshift-gitops-operator -o jsonpath='{.status.installedCSV}')
  [[ -n "$csv" && "$(oc get csv "$csv" -n openshift-gitops-operator -o jsonpath='{.status.phase}')" == "Succeeded" ]]
}
wait_for "OpenShift GitOps operator" 900 gitops_csv_succeeded
wait_for "Argo CD instance ${GITOPS_NAMESPACE}" 900 \
  oc wait argocd/openshift-gitops -n "$GITOPS_NAMESPACE" --for=jsonpath='{.status.phase}'=Available --timeout=5s

# ---------------------------------------------------------------------------------------------
# 2. Permissions and health checks for the provisioning Argo CD instance
# ---------------------------------------------------------------------------------------------
# The charts create namespaces, cluster-scoped RBAC, OLM objects in operator namespaces,
# cluster-scoped operand CRs (Istio, IstioCNI, OSSMConsole), the cluster monitoring ConfigMap,
# and RoleBindings that grant participants ClusterRoles such as `admin`. Kubernetes only lets a
# subject grant permissions it holds itself, so the application controller needs cluster-admin.
# Only the admin-only openshift-gitops instance gets this; the participants' Argo CD does not.
log "Granting cluster-admin to the openshift-gitops application controller"
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: inner-outer-loop-workshop-provisioner
  labels:
    app.kubernetes.io/part-of: inner-outer-loop-workshop
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: openshift-gitops-argocd-application-controller
    namespace: ${GITOPS_NAMESPACE}
EOF

# Argo CD has no health assessment for Application resources by default, so an app-of-apps would
# not wait for one child Application before starting the next sync wave. This check reports a
# child as Healthy only when it is Synced, Healthy and its last sync operation (including the
# readiness hook Jobs) succeeded.
log "Configuring the Application health check on the ${GITOPS_NAMESPACE} Argo CD instance"
oc patch argocd openshift-gitops -n "$GITOPS_NAMESPACE" --type merge -p "$(cat <<'EOF'
{
  "spec": {
    "resourceHealthChecks": [
      {
        "group": "argoproj.io",
        "kind": "Application",
        "check": "hs = {}\nhs.status = \"Progressing\"\nhs.message = \"\"\nif obj.status ~= nil then\n  local health = nil\n  local sync = nil\n  local phase = nil\n  if obj.status.health ~= nil then health = obj.status.health.status end\n  if obj.status.sync ~= nil then sync = obj.status.sync.status end\n  if obj.status.operationState ~= nil then phase = obj.status.operationState.phase end\n  if health == \"Healthy\" and sync == \"Synced\" and (phase == nil or phase == \"Succeeded\") then\n    hs.status = \"Healthy\"\n    hs.message = \"Synced and Healthy\"\n  else\n    hs.message = \"health=\" .. tostring(health) .. \" sync=\" .. tostring(sync) .. \" operation=\" .. tostring(phase)\n  end\nend\nreturn hs\n"
      }
    ]
  }
}
EOF
)"

# ---------------------------------------------------------------------------------------------
# 3. Secrets that must not live in Git
# ---------------------------------------------------------------------------------------------
# The gitea namespace is also declared by the platform chart; creating it here first only makes
# room for the secrets. Argo CD adopts it on the first sync.
log "Creating secrets in the gitea namespace"
oc get namespace gitea >/dev/null 2>&1 || oc create namespace gitea >/dev/null
# Participants' passwords (the same as their OpenShift passwords), used by the user-setup Job for
# their Gitea accounts and workspace credentials: key userPassword (shared) or password.<user>.
password_args=()
if [[ -n "$WORKSHOP_CREDENTIALS_FILE" ]]; then
  for user in $CONFIGURED_USERS; do
    password_args+=("--from-literal=password.${user}=$(creds_file_password "$WORKSHOP_CREDENTIALS_FILE" "$user")")
  done
else
  password_args+=("--from-literal=userPassword=${WORKSHOP_USER_PASSWORD}")
fi
oc create secret generic "$CREDENTIALS_SECRET_NAME" -n "$CREDENTIALS_SECRET_NAMESPACE" "${password_args[@]}" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
unset password_args
# A checksum of the passwords (not the passwords) goes into the root Application, so that Argo CD
# re-runs the user-setup Job whenever the passwords change.
CREDENTIALS_CHECKSUM=$(oc get secret "$CREDENTIALS_SECRET_NAME" -n "$CREDENTIALS_SECRET_NAMESPACE" -o jsonpath='{.data}' \
  | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | cut -c1-16)
# Gitea administrator password: random, generated once, never printed.
if ! oc get secret gitea-admin-password -n gitea >/dev/null 2>&1; then
  # pipefail is disabled in the subshell because `head` closing the pipe makes `tr` exit with SIGPIPE.
  ADMIN_PASSWORD="$(set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  oc create secret generic gitea-admin-password -n gitea \
    --from-literal=adminPassword="${ADMIN_PASSWORD}" >/dev/null
  unset ADMIN_PASSWORD
fi

# ---------------------------------------------------------------------------------------------
# 4. Root Application
# ---------------------------------------------------------------------------------------------
if [[ -n "$USERS_EXPLICIT_NAMES" ]]; then
  EXPLICIT_NAMES_PARAM="{${USERS_EXPLICIT_NAMES}}"
else
  EXPLICIT_NAMES_PARAM="null"
fi

log "Applying the root Application ${ROOT_APP}"
sed -e "s|repoURL: .*|repoURL: ${REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${REVISION}|" \
    "${SCRIPT_DIR}/argocd/application.yaml" \
  | awk -v count="$USERS_COUNT" -v prefix="$USERS_PREFIX" -v names="$EXPLICIT_NAMES_PARAM" \
        -v repo="$REPO_URL" -v rev="$REVISION" -v part="$GUIDE_PART" -v checksum="$CREDENTIALS_CHECKSUM" '
      /- name: users.count/          { print; getline; sub(/value: .*/, "value: \"" count "\""); print; next }
      /- name: users.prefix/         { print; getline; sub(/value: .*/, "value: " prefix); print; next }
      /- name: users.explicitNames/  { print; getline; sub(/value: .*/, "value: \"" names "\""); print; next }
      /- name: source.repoURL/       { print; getline; sub(/value: .*/, "value: " repo); print; next }
      /- name: source.targetRevision/ { print; getline; sub(/value: .*/, "value: " rev); print; next }
      /- name: guidePart/            { print; getline; sub(/value: .*/, "value: " part); print; next }
      /- name: workshopUsers.credentialsChecksum/ { print; getline; sub(/value: .*/, "value: \"" checksum "\""); print; next }
      { print }' \
  | oc apply -f -

# ---------------------------------------------------------------------------------------------
# 5. Wait until everything is Synced and Healthy
# ---------------------------------------------------------------------------------------------
print_url_template() {
  local host
  host=$(oc get route doc -n lab-guide -o jsonpath='{.spec.host}' 2>/dev/null || true)
  echo
  echo "============================================"
  echo "Lab guide URL template:"
  echo "https://${host:-<lab-guide-route-host>}?OPENSHIFT_USERNAME={username}&OPENSHIFT_PASSWORD={openshift_password}&OPENSHIFT_CONSOLE_URL={openshift_console_hostname}&OPENSHIFT_API_URL={openshift_api_url}"
  echo
  echo "Print ready-to-use URLs for every participant with:"
  echo "  ${SCRIPT_DIR}/print-user-urls.sh        (reads the passwords from the cluster)"
  echo "============================================"
}

if [[ "$WAIT" != "true" ]]; then
  log "Not waiting (--no-wait). Follow progress with: oc get applications -n ${GITOPS_NAMESPACE}"
  print_url_template
  exit 0
fi

all_green() {
  local apps
  apps=$(oc get applications.argoproj.io -n "$GITOPS_NAMESPACE" \
    -l app.kubernetes.io/part-of=inner-outer-loop-workshop --no-headers \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null)
  local root
  root=$(oc get application "$ROOT_APP" -n "$GITOPS_NAMESPACE" --no-headers \
    -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status,OP:.status.operationState.phase 2>/dev/null)
  # 4 child Applications (operators, platform, users, lab guide) plus the root.
  [[ "$(echo "$apps" | grep -c .)" -ge 4 ]] || return 1
  echo "$apps" | awk '$2 != "Synced" || $3 != "Healthy" {bad=1} END {exit bad}' || return 1
  [[ "$root" =~ ^Synced[[:space:]]+Healthy[[:space:]]+Succeeded ]] || return 1
}

log "Waiting up to ${TIMEOUT}s for all Applications to be Synced and Healthy"
deadline=$((SECONDS + TIMEOUT))
last=""
until all_green; do
  if [[ $SECONDS -ge $deadline ]]; then
    oc get applications.argoproj.io -n "$GITOPS_NAMESPACE"
    die "Timed out after ${TIMEOUT}s. Inspect the Applications above in the openshift-gitops Argo CD UI."
  fi
  status=$(oc get applications.argoproj.io -n "$GITOPS_NAMESPACE" --no-headers \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null \
    | awk '{printf "%s=%s/%s ", $1, $2, $3}')
  if [[ "$status" != "$last" ]]; then log "$status"; last="$status"; fi
  sleep 20
done

log "All Applications are Synced and Healthy"
oc get applications.argoproj.io -n "$GITOPS_NAMESPACE"
print_url_template
