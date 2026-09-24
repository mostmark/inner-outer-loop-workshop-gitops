#!/bin/bash
#
# Walks one participant through the key exercises of both parts, the way participants do: logged
# in as that user (WORKSHOP_USER_PASSWORD), running the devfile commands and the guide's steps
# inside the user's own running Dev Spaces workspace. Prints PASS/FAIL per step.
#
# Inner Loop: login, project, Inventory (Quarkus), Catalog (Spring Boot), Gateway (.NET),
#             Web UI (Node.js), health probes, externalized configuration with databases.
# Outer Loop: push to Gitea, CI pipeline, GitOps export and Argo CD sync in the participant
#             instance, CD pipelines, Service Mesh (sidecars, gateway, traffic, Kiali graph).
#
# Usage: WORKSHOP_USER_PASSWORD=... ./user-journey.sh <username> [--reset] [--keep-going] [--outer-only]
#   --reset       only return the user to the initial state (removes the user's Coolstore
#                 resources, Argo CD Applications/repositories, Gitea repositories and local
#                 changes in the workspace), then exit
#   --keep-going  continue after a failed step (default: stop at the first failure)
#   --outer-only  skip Part 1 (expects the Part 1 state in my-project-<user>, e.g. after
#                 the devfile command "Inner Loop - Deploy Coolstore")
# Exit code: number of failed steps.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

USERNAME=""
RESET=false
KEEP_GOING=false
OUTER_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --reset) RESET=true ;;
    --outer-only) OUTER_ONLY=true ;;
    --keep-going) KEEP_GOING=true ;;
    -h|--help) sed -n '3,21p' "$0"; exit 0 ;;
    *) USERNAME="$arg" ;;
  esac
done
[[ -n "$USERNAME" ]] || { echo "Usage: $0 <username> [--reset] [--keep-going]" >&2; exit 1; }
[[ -n "${WORKSHOP_USER_PASSWORD:-}" ]] || { echo "Error: WORKSHOP_USER_PASSWORD is not set." >&2; exit 1; }

API=$(oc whoami --show-server 2>/dev/null)
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
[[ -n "$API" && -n "$DOMAIN" ]] || { echo "Error: log in to the cluster first (any user) so the API and apps domain can be found." >&2; exit 1; }

DEV="my-project-${USERNAME}"
STAGING="cn-project-${USERNAME}"
DSNS="devspaces-${USERNAME}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export KUBECONFIG="${WORK}/kubeconfig"

step_fail() {
  if [[ "$KEEP_GOING" != "true" ]]; then summary; fi
}
# step <description> <command...>: like check, stops at the first failure unless --keep-going.
step() {
  local before=$FAILED
  check "$@"
  [[ $FAILED -gt $before ]] && step_fail
  return 0
}

# ---------------------------------------------------------------------------------------------
section "Log in as ${USERNAME}"
step "oc login as ${USERNAME} with the workshop password" \
  oc login "$API" -u "$USERNAME" -p "$WORKSHOP_USER_PASSWORD" --insecure-skip-tls-verify=true
step "oc whoami is ${USERNAME}" test "$(oc whoami)" = "$USERNAME"

# The participant's workspace: start it if it is stopped (as the dashboard would) and wait.
if [[ "$(oc get dw wksp-end-to-end-dev -n "$DSNS" -o jsonpath='{.spec.started}')" != "true" ]]; then
  oc patch dw wksp-end-to-end-dev -n "$DSNS" --type merge -p '{"spec":{"started":true}}' >/dev/null
fi
workspace_running() { [[ "$(oc get dw wksp-end-to-end-dev -n "$DSNS" -o jsonpath='{.status.phase}')" == "Running" ]]; }
for _ in $(seq 1 60); do workspace_running && break; sleep 10; done
step "Workspace wksp-end-to-end-dev is Running" workspace_running
POD=$(oc get pods -n "$DSNS" -l controller.devfile.io/devworkspace_name=wksp-end-to-end-dev \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
step "Workspace pod found ($POD)" test -n "$POD"

LOG="${WORK}/last.log"
# ws <command>: run a shell command in the workspace's tools container (as the participant would
# in a workspace terminal). Output goes to $LOG, and is shown when the step fails.
ws() {
  oc exec -n "$DSNS" "$POD" -c workshop-tools -- bash -c "cd /projects/workshop && $1" >"$LOG" 2>&1
  local rc=$?
  [[ $rc -ne 0 ]] && tail -25 "$LOG" | sed 's/^/       | /' >&2
  return $rc
}
# devfile <command id>: run a devfile command (commandLine in its workingDir), as "Run Task...".
devfile() {
  ws "cmd=\$(yq -r '.commands[] | select(.id == \"$1\") | .exec.commandLine' devfile.yaml) &&
      dir=\$(yq -r '.commands[] | select(.id == \"$1\") | .exec.workingDir' devfile.yaml) &&
      [ -n \"\$cmd\" ] && [ \"\$cmd\" != null ] && cd \"\$dir\" && bash -c \"\$cmd\""
}
http_ok() { # http_ok <url> [grep pattern]
  local body
  body=$(curl -sk --max-time 20 -f "$1") || return 1
  [[ -z "${2:-}" ]] || echo "$body" | grep -q "$2"
}
wait_for() { # wait_for <seconds> <command...>
  local deadline=$((SECONDS + $1)); shift
  until "$@" >/dev/null 2>&1; do [[ $SECONDS -ge $deadline ]] && return 1; sleep 10; done
}
rollout() { oc rollout status "deployment/$2" -n "$1" --timeout=600s; }

# ---------------------------------------------------------------------------------------------
reset_user() {
  section "Reset ${USERNAME} to the initial state"
  step "Devfile 'OpenShift - Cleanup'" devfile openshift---cleanup
  step "Delete the user's Gitea repositories" ws '. .tasks/workshop-env.sh &&
    for r in inventory-quarkus inventory-gitops catalog-gitops gateway-gitops web-gitops catalog-spring-boot; do
      gitea_api DELETE "/repos/${WORKSHOP_USER}/$r" >/dev/null 2>&1 || true; done'
  step "Remove the user's Argo CD repositories" ws '. .tasks/workshop-env.sh && argocd_env &&
    for r in $(workshop_argocd repo list -o url 2>/dev/null); do workshop_argocd repo rm "$r" >/dev/null 2>&1 || true; done'
  no_coolstore() {
    [[ -z "$(oc get deployment,buildconfig,route,pipeline,pipelinerun,pvc -n "$1" -o name 2>/dev/null)" ]]
  }
  step "No Coolstore resources left in ${DEV}" wait_for 300 no_coolstore "$DEV"
  step "No Coolstore resources left in ${STAGING}" wait_for 300 no_coolstore "$STAGING"
  step "No Argo CD Applications left for ${USERNAME}" ws '. .tasks/workshop-env.sh && argocd_env &&
    [ -z "$(workshop_argocd app list -o name 2>/dev/null)" ]'
}
if [[ "$RESET" == "true" ]]; then
  reset_user
  summary
fi

# ---------------------------------------------------------------------------------------------
# A workspace clones the code repository when it is first created; bring it to the latest main
# (the participant would do the same with "git pull") so the test uses the current scripts.
step "Workspace sources are up to date with main" ws "git fetch -q origin main && git reset -q --hard origin/main"

if [[ "$OUTER_ONLY" != "true" ]]; then
section "Part 1 - Inner Loop"
step "Devfile 'OpenShift - Login'" devfile openshift---login
step "Workspace oc session is ${USERNAME}" ws "test \"\$(oc whoami)\" = '${USERNAME}'"
step "Devfile 'OpenShift - Create Development Project'" devfile openshift---create-development-project
step "Workspace current project is ${DEV}" ws "test \"\$(oc project -q)\" = '${DEV}'"

step "Inventory: add the solution code" ws ".tasks/solutions/inventory-quarkus/solve.sh"
step "Inventory: devfile 'Inventory - Deploy Component'" devfile inventory---deploy-component
step "Inventory: rollout" rollout "$DEV" inventory-coolstore
step "Inventory: route answers /api/inventory/329299" wait_for 180 http_ok "http://inventory-coolstore-${DEV}.${DOMAIN}/api/inventory/329299" itemId

step "Catalog: add the solution code" ws ".tasks/solutions/catalog-spring-boot/solve.sh"
step "Catalog: devfile 'Catalog - Deploy Component'" devfile catalog---deploy-component
step "Catalog: rollout" rollout "$DEV" catalog-coolstore
step "Catalog: route answers /api/catalog" wait_for 180 http_ok "http://catalog-coolstore-${DEV}.${DOMAIN}/api/catalog" itemId

step "Gateway: devfile 'Gateway - Build and Deploy Component'" devfile gateway---build-and-deploy
step "Gateway: rollout" rollout "$DEV" gateway-coolstore
step "Gateway: route answers /api/products" wait_for 180 http_ok "http://gateway-coolstore-${DEV}.${DOMAIN}/api/products" itemId

step "Web UI: import from Git (Node.js builder)" ws ".tasks/solutions/web-nodejs/deploy.sh"
step "Web UI: build and rollout" wait_for 900 rollout "$DEV" web-coolstore
step "Web UI: route answers" wait_for 180 http_ok "http://web-coolstore-${DEV}.${DOMAIN}/" "CoolStore"

step "Health: probes for all four services" ws ".tasks/solutions/health-probes/deploy.sh"
for d in inventory-coolstore catalog-coolstore gateway-coolstore web-coolstore; do
  step "Health: $d has a readiness probe" bash -c \
    "oc get deployment $d -n $DEV -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' | grep -q /"
  step "Health: $d rolled out" rollout "$DEV" "$d"
done
step "Health: inventory readiness endpoint" wait_for 180 http_ok "http://inventory-coolstore-${DEV}.${DOMAIN}/q/health/ready" UP

step "Configuration: databases and ConfigMaps" ws ".tasks/solutions/app-config/deploy.sh"
step "Configuration: inventory-mariadb is a Deployment and ready" rollout "$DEV" inventory-mariadb
step "Configuration: catalog-postgresql is a Deployment and ready" rollout "$DEV" catalog-postgresql
step "Configuration: inventory rolled out" rollout "$DEV" inventory-coolstore
step "Configuration: catalog rolled out" rollout "$DEV" catalog-coolstore
step "Configuration: inventory uses MariaDB" bash -c \
  "oc get configmap inventory -n $DEV -o jsonpath='{.data.application\\.properties}' | grep -q mariadb"
step "Configuration: inventory still serves data" wait_for 300 http_ok "http://inventory-coolstore-${DEV}.${DOMAIN}/api/inventory/329299" itemId
step "Configuration: catalog still serves data" wait_for 300 http_ok "http://catalog-coolstore-${DEV}.${DOMAIN}/api/catalog" itemId
step "Configuration: web UI through the gateway" wait_for 180 http_ok "http://gateway-coolstore-${DEV}.${DOMAIN}/api/products" itemId

fi

# ---------------------------------------------------------------------------------------------
section "Part 2 - Outer Loop"
if [[ "$OUTER_ONLY" == "true" ]]; then
  step "Devfile 'OpenShift - Login'" devfile openshift---login
fi
step "CI: push inventory to Gitea and create the pipeline" ws ".tasks/solutions/continuous-integration/solve.sh"
step "CI: repository ${USERNAME}/inventory-quarkus has a main branch" wait_for 120 \
  http_ok "https://gitea-server-gitea.${DOMAIN}/api/v1/repos/${USERNAME}/inventory-quarkus/branches/main"
pipelinerun_succeeded() { # pipelinerun_succeeded <name>
  [[ "$(oc get pipelinerun "$1" -n "$STAGING" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')" == "True" ]]
}
PR=$(oc create -n "$STAGING" -o name -f - <<'YAML' 2>/dev/null | cut -d/ -f2
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: inventory-pipeline-
spec:
  pipelineRef:
    name: inventory-pipeline
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: inventory-pipeline-pvc
YAML
)
step "CI: PipelineRun started ($PR)" test -n "$PR"
step "CI: PipelineRun $PR succeeded (git-clone, s2i-java)" wait_for 1500 pipelinerun_succeeded "$PR"
step "CI: image inventory-coolstore in ${STAGING}" bash -c "oc get istag inventory-coolstore:latest -n $STAGING >/dev/null"

step "GitOps: export and push the configuration, create the Argo CD Applications" ws ".tasks/solutions/gitops/solve.sh"
step "GitOps: repository ${USERNAME}/inventory-gitops has the manifests" wait_for 120 \
  http_ok "https://gitea-server-gitea.${DOMAIN}/api/v1/repos/${USERNAME}/inventory-gitops/contents/deployment.yaml?ref=main"
step "GitOps: no DeploymentConfig in the export" ws "! grep -rl 'kind: DeploymentConfig' labs/gitops"
step "GitOps: Application inventory-${USERNAME} in the participant Argo CD" ws \
  ". .tasks/workshop-env.sh && argocd_env && workshop_argocd app get inventory-${USERNAME} >/dev/null"
step "GitOps: sync inventory-${USERNAME} (as in the Argo CD UI)" ws \
  ". .tasks/workshop-env.sh && argocd_env && workshop_argocd app sync inventory-${USERNAME} >/dev/null &&
   workshop_argocd app wait inventory-${USERNAME} --health --timeout 600 >/dev/null"
step "GitOps: inventory rolled out in ${STAGING}" rollout "$STAGING" inventory-coolstore

step "CD: Argo CD Task, ConfigMap and extended pipeline" ws ".tasks/solutions/continuous-deployment/solve.sh"
step "CD: run the CD pipelines of all services" ws ".tasks/solutions/continuous-deployment/deploy.sh"
last_inventory_run() {
  oc get pipelinerun -n "$STAGING" -l tekton.dev/pipeline=inventory-pipeline \
    --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'
}
step "CD: inventory PipelineRun with Argo CD sync succeeded" wait_for 1500 pipelinerun_succeeded "$(last_inventory_run)"
for app in inventory catalog gateway web; do
  step "CD: Argo CD Application ${app}-${USERNAME} Synced and Healthy" ws \
    ". .tasks/workshop-env.sh && argocd_env &&
     workshop_argocd app get ${app}-${USERNAME} -o json | yq -r '.status.sync.status + \"/\" + .status.health.status' | grep -qx Synced/Healthy"
done
for d in inventory-coolstore catalog-coolstore gateway-coolstore web-coolstore; do
  step "CD: $d rolled out in ${STAGING}" rollout "$STAGING" "$d"
done
step "CD: gateway in ${STAGING} answers" wait_for 300 http_ok "http://gateway-coolstore-${STAGING}.${DOMAIN}/api/products" itemId

step "Mesh: sidecar injection, per-user ingress gateway, Gateway/VirtualServices" ws ".tasks/solutions/service-mesh/deploy.sh"
for d in inventory-coolstore catalog-coolstore gateway-coolstore; do
  step "Mesh: $d rolled out with a sidecar (2/2)" bash -c "oc rollout status deployment/$d -n $STAGING --timeout=600s >/dev/null &&
    oc get pods -n $STAGING --no-headers | awk '\$1 ~ /^$d-/ && \$3 == \"Running\" {print \$2}' | grep -qx 2/2"
done
step "Mesh: ingress gateway rolled out" rollout "$STAGING" istio-ingressgateway
GW="http://istio-ingressgateway-${STAGING}.${DOMAIN}/api/products"
step "Mesh: products through the Istio ingress gateway" wait_for 300 http_ok "$GW" itemId
step "Mesh: devfile 'Gateway - Generate Traffic' (90 s)" ws \
  "cmd=\$(yq -r '.commands[] | select(.id == \"gateway---generate-traffic\") | .exec.commandLine' devfile.yaml) &&
   cd .tasks && timeout 90 bash -c \"\$cmd\"; test \$? -eq 124"
kiali_graph() {
  local token
  token=$(oc whoami -t)
  curl -sk --max-time 30 -H "Authorization: Bearer ${token}" \
    "https://kiali-istio-system.${DOMAIN}/api/namespaces/graph?namespaces=${STAGING}&graphType=workload&duration=600s" \
    > "${WORK}/graph.json" && jq -e '.elements.edges | length > 0' "${WORK}/graph.json"
}
step "Mesh: Kiali shows traffic in ${STAGING} (graph has edges)" wait_for 300 kiali_graph
kiali_edge() { # kiali_edge <source workload> <target workload prefix>
  jq -e --arg s "$1" --arg t "$2" '
    (.elements.nodes | map({key: .data.id, value: (.data.workload // .data.service // "")}) | from_entries) as $n
    | [.elements.edges[] | select($n[.data.source] == $s and ($n[.data.target] | startswith($t)))] | length > 0' \
    "${WORK}/graph.json"
}
step "Mesh: Kiali graph has istio-ingressgateway -> gateway-coolstore" kiali_edge istio-ingressgateway gateway-coolstore
step "Mesh: Kiali graph has gateway-coolstore -> inventory-coolstore" kiali_edge gateway-coolstore inventory-coolstore
step "Mesh: Kiali graph has gateway-coolstore -> catalog-coolstore" kiali_edge gateway-coolstore catalog-coolstore

summary
