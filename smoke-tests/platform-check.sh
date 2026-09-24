#!/bin/bash
#
# Platform smoke test of the Inner & Outer Loop workshop (run as cluster-admin).
#
# Verifies that all Argo CD Applications are Synced and Healthy, every operator CSV Succeeded and
# every operand is Ready, the routes answer, the per-user resources exist for every configured
# user, the lab guide renders with per-user values, and no pod in a workshop namespace is
# crash-looping.
#
# Usage: ./platform-check.sh [--users N] [--prefix P] [--names a,b]
#        (default: the users configured in the root Application)
# Exit code: number of failed checks (0 = all passed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../lib/credentials.sh
source "${SCRIPT_DIR}/../lib/credentials.sh"

parse_user_args "$@"
require_admin

section "Argo CD Applications"
apps=$(oc get applications.argoproj.io -n openshift-gitops --no-headers \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null)
for app in inner-outer-loop-workshop workshop-operators workshop-platform workshop-users workshop-lab-guide; do
  line=$(echo "$apps" | awk -v a="$app" '$1 == a')
  check "Application $app is Synced/Healthy" test "$(echo "$line" | awk '{print $2"/"$3}')" = "Synced/Healthy"
done

section "Operators"
for entry in openshift-gitops-operator/openshift-gitops-operator openshift-operators/devspaces \
             openshift-operators/openshift-pipelines-operator-rh openshift-operators/servicemeshoperator3 \
             kiali-operator/kiali-ossm gitea-operator/gitea-operator; do
  ns=${entry%%/*}; sub=${entry#*/}
  csv=$(oc get subscriptions.operators.coreos.com "$sub" -n "$ns" -o jsonpath='{.status.installedCSV}' 2>/dev/null)
  check "CSV of $sub ($csv) Succeeded" test "$(oc get csv "$csv" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Succeeded"
done
check "DevWorkspace operator CSV Succeeded" bash -c \
  "oc get csv -n openshift-operators --no-headers | awk '/^devworkspace-operator/ {print \$NF}' | grep -qx Succeeded"

section "Operands"
check "CheCluster devspaces is Active" test "$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.chePhase}')" = "Active"
check "Istio default is Ready" test "$(oc get istio default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True"
check "IstioCNI default is Ready" test "$(oc get istiocni default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True"
check "Kiali deployment available" deployment_available istio-system kiali
check "OSSMConsole plugin deployed" bash -c "oc get consoleplugin ossmconsole >/dev/null"
check "TektonConfig config is Ready" test "$(oc get tektonconfig config -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True"
check "Participant Argo CD is Available" test "$(oc get argocd argocd -n argocd -o jsonpath='{.status.phase}')" = "Available"
check "Gitea admin set up" test "$(oc get gitea gitea-server -n gitea -o jsonpath='{.status.adminSetupComplete}')" = "true"
check "Gitea deployment available" deployment_available gitea gitea-server
check "Nexus deployment available" deployment_available nexus nexus
check "User workload monitoring enabled" bash -c \
  "oc get pods -n openshift-user-workload-monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -q Running"
check "Pipelines console plugin enabled" bash -c \
  "oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' | grep -q pipelines-console-plugin"
check "Java 21 builder tag openshift/java:openjdk-21-ubi9" bash -c "oc get istag java:openjdk-21-ubi9 -n openshift >/dev/null"
check "Database templates in openshift" bash -c "oc get template coolstore-mariadb coolstore-postgresql -n openshift >/dev/null"

section "Routes"
DOMAIN=$(apps_domain)
check_http "Lab guide"            "https://$(oc get route doc -n lab-guide -o jsonpath='{.spec.host}')/"                 200
check_http "Dev Spaces dashboard" "https://devspaces.${DOMAIN}/"                                                        200
check_http "Gitea"                "https://gitea-server-gitea.${DOMAIN}/api/v1/version"                                 200
check_http "Argo CD (participants)" "https://argocd-server-argocd.${DOMAIN}/healthz"                                   200
check_http "Argo CD login page"   "https://argocd-server-argocd.${DOMAIN}/auth/login"                                   "200 302 303"
check_http "Kiali"                "https://kiali-istio-system.${DOMAIN}/"                                               200
check "Nexus Maven group readable anonymously" in_cluster_http \
  "http://nexus.nexus.svc:8081/repository/maven-all-public/org/apache/maven/plugins/maven-clean-plugin/maven-metadata.xml" 200

section "Per-user resources"
for user in $USERS; do
  for ns in "my-project-$user" "cn-project-$user" "devspaces-$user"; do
    check "$user: namespace $ns" bash -c "oc get namespace $ns >/dev/null"
  done
  check "$user: admin in my-project-$user" can_i_as "$user" create deployments "my-project-$user"
  check "$user: edit in cn-project-$user" can_i_as "$user" create deployments "cn-project-$user"
  check "$user: cn-project in the mesh" test \
    "$(oc get namespace "cn-project-$user" -o jsonpath='{.metadata.labels.istio-discovery}')" = "enabled"
  check "$user: cn-project managed by participant Argo CD" test \
    "$(oc get namespace "cn-project-$user" -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by}')" = "argocd"
  check "$user: AppProject cn-project-$user" bash -c "oc get appproject cn-project-$user -n argocd >/dev/null"
  check "$user: Argo CD token secret" bash -c "oc get secret argocd-env-secret -n cn-project-$user >/dev/null"
  check "$user: workspace credentials" bash -c \
    "oc get secret workshop-credentials workshop-git-credentials -n devspaces-$user >/dev/null && oc get configmap workshop-env -n devspaces-$user >/dev/null"
  # The password bootstrap.sh stored for the user (shared or per user) reached the workspace.
  check "$user: workspace has the user's current password" bash -c \
    "[ -n \"\$1\" ] && [ \"\$(oc get secret workshop-credentials -n devspaces-$user -o jsonpath='{.data.WORKSHOP_PASSWORD}' | base64 -d)\" = \"\$1\" ]" \
    _ "$(creds_cluster_password "$user" 2>/dev/null)"
  check "$user: PodMonitor for Istio proxies" bash -c "oc get podmonitor istio-proxies-monitor -n cn-project-$user >/dev/null"
  check "$user: Gitea account" in_cluster_http "http://gitea-server.gitea.svc:3000/api/v1/users/$user" 200
  started=$(oc get dw wksp-end-to-end-dev -n "devspaces-$user" -o jsonpath='{.spec.started}' 2>/dev/null)
  phase=$(oc get dw wksp-end-to-end-dev -n "devspaces-$user" -o jsonpath='{.status.phase}' 2>/dev/null)
  check "$user: Dev Spaces URLs for the workspace (ConfigMap workshop-devspaces-env)" bash -c \
    "oc get configmap workshop-devspaces-env -n devspaces-$user -o jsonpath='{.data.CHE_DASHBOARD_URL}' | grep -q '^https://.*/dashboard/\$'"
  if [[ "$started" == "true" ]]; then
    check "$user: workspace wksp-end-to-end-dev Running" test "$phase" = "Running"
    # Without CHE_DASHBOARD_URL the editor cannot open terminals (KNOWN-ISSUES K18).
    check "$user: workspace container has CHE_DASHBOARD_URL" bash -c \
      "oc exec -n devspaces-$user \$(oc get pods -n devspaces-$user -l controller.devfile.io/devworkspace_name=wksp-end-to-end-dev -o name | head -1) -c workshop-tools -- printenv CHE_DASHBOARD_URL | grep -q /dashboard/"
  else
    check "$user: workspace wksp-end-to-end-dev exists (not started: $phase)" test -n "$phase"
  fi
done

section "Lab guide"
GUIDE=$(oc get route doc -n lab-guide -o jsonpath='{.spec.host}')
check "URL template ConfigMap" bash -c "oc get configmap lab-guide-url-template -n lab-guide -o jsonpath='{.data.url-template}' | grep -q OPENSHIFT_USERNAME"
check_http "Start page" "https://${GUIDE}/modules/index.html" 200
first_user=$(echo "$USERS" | awk '{print $1}')
if [[ -n "$first_user" ]]; then
  # Passwords from WORKSHOP_CREDENTIALS_FILE, the cluster Secret or WORKSHOP_USER_PASSWORD.
  url=$("${SCRIPT_DIR}/../print-user-urls.sh" --names "$first_user" 2>/dev/null | awk '{print $2}')
  check "print-user-urls.sh prints a URL for $first_user" test -n "$url"
  check "Per-user URL renders" bash -c "curl -skf '$url' >/dev/null"
fi
# The guide shows the part configured on the root Application (guidePart: all, inner, outer). Pages
# of that part must be served, pages of the other part must not exist.
PART=$(oc get application inner-outer-loop-workshop -n openshift-gitops \
  -o jsonpath='{.spec.source.helm.parameters[?(@.name=="guidePart")].value}' 2>/dev/null)
PART=${PART:-all}
check "Lab guide pod serves part '$PART'" test \
  "$(oc get deployment lab-guide -n lab-guide -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WORKSHOP_PART")].value}')" = "$PART"
INNER_PAGES="inner-loop-01-introduction inner-loop-02-developer-workspace inner-loop-03-inventory-quarkus
  inner-loop-04-catalog-spring-boot inner-loop-05-gateway-dotnet inner-loop-06-webui-deployment
  inner-loop-07-app-health inner-loop-08-app-config"
OUTER_PAGES="outer-loop-01-introduction outer-loop-02-developer-workspace outer-loop-03-continuous-integration
  outer-loop-04-gitops-workflow outer-loop-05-continuous-delivery outer-loop-06-service-mesh"
case "$PART" in
  inner) SHOWN="index $INNER_PAGES"; HIDDEN="$OUTER_PAGES" ;;
  outer) SHOWN="index $OUTER_PAGES"; HIDDEN="$INNER_PAGES" ;;
  *)     SHOWN="index $INNER_PAGES $OUTER_PAGES"; HIDDEN="" ;;
esac
# The theme replaces %tokens% with URL parameters in the browser; the served pages must carry them.
for page in $SHOWN; do
  check "Page $page served" bash -c "curl -skf https://${GUIDE}/modules/${page}.html | grep -q '<article'"
done
for page in $HIDDEN; do
  check_http "Page $page of the other part is not served" "https://${GUIDE}/modules/${page}.html" 404
done
check "Pages carry the per-user tokens" bash -c \
  "curl -skf https://${GUIDE}/modules/index.html | grep -q '%openshift_username%'"
check "Head script derives the apps domain" bash -c \
  "curl -skf https://${GUIDE}/modules/index.html | grep -q OPENSHIFT_APPS_DOMAIN"

section "Pods"
for ns in lab-guide workshop-setup openshift-devspaces istio-system istio-cni argocd gitea nexus kiali-operator gitea-operator \
          $(for u in $USERS; do echo "my-project-$u cn-project-$u devspaces-$u"; done); do
  bad=$(oc get pods -n "$ns" --no-headers 2>/dev/null | awk '$3 ~ /CrashLoopBackOff|Error|ImagePullBackOff|ErrImagePull/ || $4 > 5 {print $1"("$3","$4")"}')
  check "No crash-looping pods in $ns" test -z "$bad"
  [[ -n "$bad" ]] && echo "       $bad"
done

summary
