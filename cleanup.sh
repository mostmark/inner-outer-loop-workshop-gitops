#!/bin/bash
#
# Removes the Inner & Outer Loop workshop from the cluster.
#
# Cleanup is GitOps-style: deleting the root Application makes Argo CD delete the child
# Applications and, through their finalizers, every resource they manage (namespaces, operands,
# RBAC, Subscriptions ...). This script does that first and waits for it. It then removes what
# Argo CD cannot prune cleanly, because OLM or the operators created it rather than Git:
#
#   - the operators' ClusterServiceVersions (deleting a Subscription leaves the operator
#     installed) and the DevWorkspace operator dependency OLM added,
#   - the operator namespaces kept with Delete=false (kiali-operator, gitea-operator), so the
#     operators could still process their resources' finalizers during the Argo CD cleanup,
#   - objects created by the operators themselves (TektonConfig, the openshift-pipelines
#     namespace, DevWorkspace webhooks, console plugin entries),
#   - the Java 21 tag added to openshift/java and the operators' CRDs (unless --keep-crds),
#   - OpenShift GitOps itself, installed by bootstrap.sh (unless --keep-gitops).
#
# Usage: ./cleanup.sh [--yes] [--keep-gitops] [--keep-crds] [--timeout SECONDS]

set -uo pipefail

GITOPS_NAMESPACE=openshift-gitops
ROOT_APP=inner-outer-loop-workshop
ASSUME_YES=false
KEEP_GITOPS=false
KEEP_CRDS=false
TIMEOUT=1800

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=true; shift ;;
    --keep-gitops) KEEP_GITOPS=true; shift ;;
    --keep-crds) KEEP_CRDS=true; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() { echo "[$(date +%H:%M:%S)] $*"; }

command -v oc >/dev/null 2>&1 || { echo "Error: 'oc' CLI not found." >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "Error: not logged in to OpenShift." >&2; exit 1; }
[[ "$(oc auth can-i '*' '*' --all-namespaces)" == "yes" ]] || { echo "Error: cluster-admin permissions are required." >&2; exit 1; }

log "Logged in as: $(oc whoami)"
log "Server:       $(oc whoami --show-server)"
if [[ "$ASSUME_YES" != "true" ]]; then
  echo
  echo "WARNING: this removes the whole workshop, including every participant's work,"
  echo "the workshop operators$([[ "$KEEP_GITOPS" == "true" ]] || echo " and OpenShift GitOps")."
  read -rp "Are you sure? (y/N): " CONFIRM
  [[ "$CONFIRM" == [yY] ]] || { echo "Aborted."; exit 0; }
fi

wait_gone() {
  # wait_gone <description> <command that prints remaining items>
  local description="$1"; shift
  local deadline=$((SECONDS + TIMEOUT)) remaining
  while remaining=$("$@" 2>/dev/null) && [[ -n "$remaining" ]]; do
    if [[ $SECONDS -ge $deadline ]]; then
      log "Timed out waiting for ${description}. Still present:"
      echo "$remaining"
      return 1
    fi
    sleep 15
  done
  log "${description}: gone"
}

# drain <description> <resource> <operator CSV prefix>: waits until no <resource> is left. If the
# operator that owns their finalizers is no longer installed (e.g. an interrupted cleanup), the
# orphaned finalizers are removed instead of waiting forever.
drain() {
  local description="$1" resource="$2" csv_prefix="$3" items
  items() { oc get "$resource" -A --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name 2>/dev/null; }
  if ! oc get csv -A --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | grep -q "^${csv_prefix}"; then
    items | while read -r ns name; do
      [[ -z "$name" ]] && continue
      log "Operator for ${resource} is gone; removing finalizers of ${ns}/${name}"
      if [[ "$ns" == "<none>" ]]; then
        oc patch "$resource" "$name" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null
      else
        oc patch "$resource" "$name" -n "$ns" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null
      fi
    done
  fi
  wait_gone "$description" items
}

# ---------------------------------------------------------------------------------------------
# 1. GitOps cleanup: delete the root Application
# ---------------------------------------------------------------------------------------------
if oc get application "$ROOT_APP" -n "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
  log "Deleting the root Application ${ROOT_APP} (Argo CD prunes everything it manages)"
  oc delete application "$ROOT_APP" -n "$GITOPS_NAMESPACE" --wait=false
fi
workshop_apps() {
  oc get applications.argoproj.io -n "$GITOPS_NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null \
    | grep -E "^(${ROOT_APP}|workshop-)"
}
wait_gone "workshop Applications" workshop_apps

workshop_namespaces() {
  oc get namespaces --no-headers -o custom-columns=NAME:.metadata.name \
    | grep -E '^(my-project-|cn-project-|devspaces-)' ;
  for ns in lab-guide workshop-setup openshift-devspaces istio-system istio-cni argocd gitea nexus; do
    oc get namespace "$ns" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null
  done
}
wait_gone "workshop namespaces" workshop_namespaces

# ---------------------------------------------------------------------------------------------
# 2. What Argo CD cannot prune: operators installed through OLM
# ---------------------------------------------------------------------------------------------
log "Removing TektonConfig (lets the Pipelines operator clean up openshift-pipelines)"
oc delete tektonconfig config --ignore-not-found --wait=true --timeout=300s
# The operator removes its TektonInstallerSets asynchronously; its CSV must stay until they are gone.
drain "TektonInstallerSets" tektoninstallersets.operator.tekton.dev openshift-pipelines-operator-rh

delete_operator() {
  # delete_operator <namespace> <package> : Subscriptions and CSVs of one OLM package
  local ns="$1" pkg="$2" sub csv
  for sub in $(oc get subscriptions.operators.coreos.com -n "$ns" --no-headers \
      -o custom-columns=NAME:.metadata.name,PKG:.spec.name 2>/dev/null | awk -v p="$pkg" '$2 == p {print $1}'); do
    oc delete subscriptions.operators.coreos.com "$sub" -n "$ns" --ignore-not-found
  done
  for csv in $(oc get csv -n "$ns" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | grep -E "^${3:-$pkg}"); do
    oc delete csv "$csv" -n "$ns" --ignore-not-found
  done
}
log "Removing operator Subscriptions and ClusterServiceVersions"
delete_operator openshift-operators devspaces devspacesoperator
delete_operator openshift-operators devworkspace-operator devworkspace-operator
delete_operator openshift-operators openshift-pipelines-operator-rh openshift-pipelines-operator-rh
delete_operator openshift-operators servicemeshoperator3 servicemeshoperator3
delete_operator kiali-operator kiali-ossm kiali-operator
delete_operator gitea-operator gitea-operator gitea-operator

log "Removing operator namespaces kept during the Argo CD cleanup"
oc delete namespace kiali-operator gitea-operator --ignore-not-found --wait=false

log "Removing objects the operators created themselves"
oc delete namespace openshift-pipelines --ignore-not-found --wait=false
# DevWorkspace operator webhooks and services (same steps as the Dev Spaces uninstall docs).
oc delete deployment devworkspace-webhook-server -n openshift-operators --ignore-not-found
oc delete mutatingwebhookconfigurations controller.devfile.io --ignore-not-found
oc delete validatingwebhookconfigurations controller.devfile.io --ignore-not-found
oc delete all --selector app.kubernetes.io/part-of=devworkspace-operator,app.kubernetes.io/name=devworkspace-webhook-server \
  -n openshift-operators --ignore-not-found >/dev/null
oc delete serviceaccounts devworkspace-webhook-server -n openshift-operators --ignore-not-found
oc delete clusterrole devworkspace-webhook-server --ignore-not-found
oc delete clusterrolebinding devworkspace-webhook-server --ignore-not-found
# Console plugins the workshop enabled (the ConsolePlugin objects went with their operators).
for plugin in pipelines-console-plugin ossmconsole; do
  idx=$(oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' \
    | tr -d '[]"' | tr ',' '\n' | grep -n -x "$plugin" | cut -d: -f1)
  [[ -n "$idx" ]] && oc patch consoles.operator.openshift.io cluster --type json \
    -p "[{\"op\":\"remove\",\"path\":\"/spec/plugins/$((idx - 1))\"}]" >/dev/null && log "Disabled console plugin $plugin"
done
# ConsolePlugins, SCC, webhooks and cluster RBAC the Pipelines, DevWorkspace, Gitea and Service
# Mesh operators created at run time (not part of their CSVs, so OLM does not remove them).
oc delete consoleplugin pipelines-console-plugin ossmconsole --ignore-not-found
oc delete scc pipelines-scc --ignore-not-found
oc delete mutatingwebhookconfiguration webhook.operator.tekton.dev --ignore-not-found
oc delete validatingwebhookconfiguration config.webhook.operator.tekton.dev validation.webhook.operator.tekton.dev \
  namespace.operator.tekton.dev --ignore-not-found
for kind in clusterrole clusterrolebinding; do
  oc get "$kind" --no-headers -o custom-columns=NAME:.metadata.name \
    | grep -E '^(devworkspace-controller-|devspaces-(edit|view)$|gitea-operator-|openshift-pipelines-|pipelines-scc-|tekton-|servicemesh-|sail-|kiali-)' \
    | xargs -r oc delete "$kind" --ignore-not-found >/dev/null
done
# Java 21 builder tag added by the platform chart's cluster-integration Job.
oc tag -d openshift/java:openjdk-21-ubi9 >/dev/null 2>&1 && log "Removed openshift/java:openjdk-21-ubi9"

if [[ "$KEEP_CRDS" != "true" ]]; then
  log "Removing the operators' CRDs"
  oc get crd --no-headers -o custom-columns=NAME:.metadata.name \
    | grep -E '\.(devfile\.io|eclipse\.che|tekton\.dev|pipelinesascode\.tekton\.dev|istio\.io|sailoperator\.io|kiali\.io|pfe\.rhpds\.com)$' \
    | xargs -r oc delete crd --ignore-not-found --wait=false
fi

# ---------------------------------------------------------------------------------------------
# 3. OpenShift GitOps (installed by bootstrap.sh)
# ---------------------------------------------------------------------------------------------
if [[ "$KEEP_GITOPS" != "true" ]]; then
  log "Removing OpenShift GitOps"
  oc delete clusterrolebinding inner-outer-loop-workshop-provisioner --ignore-not-found
  # The operator re-creates its default instance while it runs, so disable the default instance
  # first and let the operator remove it (and its finalizer) before uninstalling the operator.
  oc patch subscriptions.operators.coreos.com openshift-gitops-operator -n openshift-gitops-operator --type merge \
    -p '{"spec":{"config":{"env":[{"name":"DISABLE_DEFAULT_ARGOCD_INSTANCE","value":"true"}]}}}' >/dev/null 2>&1
  oc delete argocd --all -A --ignore-not-found --wait=false >/dev/null 2>&1
  drain "Argo CD instances" argocds.argoproj.io openshift-gitops-operator
  delete_operator openshift-gitops-operator openshift-gitops-operator openshift-gitops-operator
  oc delete consoleplugin gitops-plugin --ignore-not-found
  oc delete namespace "$GITOPS_NAMESPACE" openshift-gitops-operator --ignore-not-found --wait=false
  for kind in clusterrole clusterrolebinding; do
    oc get "$kind" --no-headers -o custom-columns=NAME:.metadata.name \
      | grep -E '^(openshift-gitops-|gitops-service-|gitopsservices\.)' \
      | xargs -r oc delete "$kind" --ignore-not-found >/dev/null
  done
  if [[ "$KEEP_CRDS" != "true" ]]; then
    oc get crd --no-headers -o custom-columns=NAME:.metadata.name \
      | grep -E '\.argoproj\.io$|^gitopsservices\.pipelines\.openshift\.io$' | xargs -r oc delete crd --ignore-not-found --wait=false
  fi
else
  oc delete clusterrolebinding inner-outer-loop-workshop-provisioner --ignore-not-found
fi

namespaces_left() {
  for ns in kiali-operator gitea-operator openshift-pipelines $([[ "$KEEP_GITOPS" == "true" ]] || echo "$GITOPS_NAMESPACE openshift-gitops-operator"); do
    oc get namespace "$ns" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null
  done
}
wait_gone "operator namespaces" namespaces_left

echo
echo "============================================"
echo "Workshop cleanup complete."
echo "Kept by design: the pre-created OpenShift users, the openshift-user-workload-monitoring"
echo "namespace (managed by the cluster monitoring operator)."
echo "============================================"
