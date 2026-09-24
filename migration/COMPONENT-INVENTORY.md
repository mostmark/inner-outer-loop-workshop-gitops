# Component inventory

What the old `workshop-operator` (branch 2.13, `config/samples/workshop_v1_end-to-end-developer.yaml`)
provisioned for the End-to-End Developer Workshop, what the guides and the devfile expect, and
where each item lives in the new GitOps setup. Sources: `controllers/*.go`, `common/**`,
`config/samples`, `htpasswd/`, the Inner Loop guide 6.9, the Outer Loop guide 6.11 and the code
repository 6.11 (SHAs in [MIGRATION.md](MIGRATION.md)).

Chart abbreviations: **ops** = `charts/workshop-operators`, **plat** = `charts/workshop-platform`,
**users** = `charts/workshop-users`, **guide** = `charts/lab-guide`, **boot** = `bootstrap.sh`.

## 1. Operators

The old operator created each Subscription itself with a pinned `startingCSV` and Manual
approval, then approved the InstallPlan in code (`controllers/installplan.go`). The sample CR
(OpenShift 4.20/4.21 variant) used the versions in the "old" columns. New channels were verified
with `oc get packagemanifest <package> -o yaml` on OpenShift 4.22.14.

| Operator | Package / catalog | Old: channel, CSV, namespace, approval | New: channel, namespace, approval | Where |
|---|---|---|---|---|
| Workshop operator | custom image | 2.13 in `workshop-infra` | **dropped** (replaced by GitOps) | - |
| OpenShift GitOps | `openshift-gitops-operator` / redhat-operators | `gitops-1.6`, v1.6.6, `openshift-operators`, Manual (auto-approved) | `gitops-1.21` (v1.21.4, Argo CD 3.4.7), `openshift-gitops-operator`, Automatic | boot |
| Dev Spaces | `devspaces` / redhat-operators | `stable`, v3.22.0, own ns `openshift-devspaces` + OperatorGroup, Manual | `stable` (only channel; v3.30.1), `openshift-operators` (AllNamespaces, the supported mode), Automatic | ops |
| DevWorkspace operator | `devworkspace-operator` | dependency, resolved by OLM | dependency, `fast` v0.43.0, resolved by OLM | (OLM) |
| OpenShift Pipelines | `openshift-pipelines-operator-rh` / redhat-operators | `pipelines-1.20`, v1.20.3, `openshift-operators`, Manual | `pipelines-1.24` (v1.24.0), `openshift-operators`, Automatic | ops |
| Service Mesh 3 | `servicemeshoperator3` / redhat-operators | `stable`, v3.2.1, `openshift-operators`, Manual | `stable-3.4` (v3.4.2), `openshift-operators`, Automatic | ops |
| Kiali | `kiali-ossm` / redhat-operators | `stable`, v2.22.1, `openshift-operators`, Manual | `stable` (`candidate` is a preview), **Manual + `startingCSV: kiali-operator.v2.27.4`**, own ns `kiali-operator`, approval Job | ops |
| Gitea | `gitea-operator` | Ansible operator image `quay.io/gpte-devops-automation/gitea-operator:v1.2.3` deployed as a plain Deployment in `gitea`, CRD `giteas.gpte.opentlc.com/v1` | rhpds Gitea operator v2.3.2 via CatalogSource `quay.io/rhpds/gitea-catalog:v2.3.2`, channel `stable`, ns `gitea-operator`, Automatic, CRD `gitea.pfe.rhpds.com/v1` | ops |
| Nexus | Ansible operator image `nexus-operator:v0.10` of the old organisation in `opentlc-shared`, CRD `nexus.gpte.opentlc.com` | **dropped**: plain manifests (no maintained operator, D7) | plat |
| Serverless | `serverless-operator` (only if `serverless.enabled`) | not enabled in the sample CR | **dropped** (not used by either guide) | - |
| Elasticsearch / Jaeger | `elasticsearch-operator`, `jaeger-product` | code commented out in 2.13 | **dropped** (no tracing step in the guides) | - |
| Istio Workspace (`ike`) | `istio-workspace-operator` | only if `istioWorkspace.enabled`; not enabled | **dropped** | - |
| CodeReady Workspaces user sync (Keycloak) | - | unused leftover (`NewUser`) | **dropped** | - |

## 2. Instance custom resources

| Kind (old API) | Old settings that matter | New object (API) | Where |
|---|---|---|---|
| `CheCluster` `devspaces` (`org.eclipse.che/v1` via Go types) in `openshift-devspaces` | namespace `<username>devspaces`, auto-provision, PVC strategy `common` 10Gi, `CHE_LIMITS_USER_WORKSPACES_RUN_COUNT=2`, idle timeout ~8 h, `secondsOfInactivityBeforeIdling: -1` | `CheCluster` `devspaces` (`org.eclipse.che/v2`): namespace template `devspaces-<username>`, `per-user` PVC 10Gi (successor of `common`), 2 running workspaces per user, no idling (`-1`), container build disabled (not used by the labs) | plat |
| `Istio` `default` (`sailoperator.io/v1`) | ns `istio-system`, `v1.27-latest`, `meshConfig.discoverySelectors: istio-discovery=enabled` | same, `v1.30-latest` (OSSM 3.4), `updateStrategy: InPlace` | plat |
| `IstioCNI` `default` | ns `istio-cni`, `v1.27-latest` | same, `v1.30-latest` | plat |
| Namespace `ztunnel` | created, never used (no `ZTunnel` CR) | **dropped** | - |
| `Kiali` `kiali-user-workload-monitoring` (`kiali.io/v1alpha1`) in `istio-system` | Prometheus = Thanos querier with `use_kiali_token`, `thanos_proxy`, discovery selectors, validations ignore `KIA0302`, `KIA1301` | `Kiali` `kiali` with the same settings, `auth.strategy: openshift`, grafana/tracing disabled; route `kiali-istio-system.<apps>` | plat |
| ClusterRoleBinding `kiali-monitoring-rbac` | SA `kiali-service-account` → `cluster-monitoring-view` | same | plat |
| `OSSMConsole` `ossmconsole` in `openshift-operators` | embedded Kiali console plugin | `OSSMConsole` `ossmconsole` in `istio-system`; the guide keeps using the standalone Kiali (plugin lacks actions) | plat |
| `Telemetry` `enable-prometheus-metrics`, `ServiceMonitor` `istiod-monitor`, `PodMonitor` `proxies-monitor` (istio-system) | Istio metrics for user workload monitoring | same (`telemetry.istio.io/v1`, PodMonitor renamed `istio-proxies-monitor`) | plat |
| ConfigMap `cluster-monitoring-config` (openshift-monitoring) | `enableUserWorkload: true` | same | plat |
| `ArgoCD` `argocd` (`argoproj.io/v1alpha1`) in `argocd` | `server.insecure`, route, RBAC per user, `scopes: [preferred_username]`, local accounts `user<N>` with **bcrypt workshop password** (`argocd-secret`), Dex disabled | `ArgoCD` `argocd` (`argoproj.io/v1beta1`): Dex `openShiftOAuth`, same per-user RBAC (plus `logs`, `applicationsets`, project-scoped `repositories`), local accounts with `apiKey` only, tokens by Job (D8) | plat, users |
| `AppProject` `cn-project<N>` | destination `cn-project<N>`, `sourceRepos: ['*']` | `AppProject` `cn-project-<user>`: destination `cn-project-<user>`, sourceRepos restricted to the user's Gitea repositories, no cluster resources | users |
| Console plugin `pipelines-console-plugin` | patched into `consoles.operator.openshift.io/cluster` | appended by the `cluster-integration` Job | plat |
| `Gitea` `gitea-server` (`gpte.opentlc.com/v1`) in `gitea` | `giteaSsl`, 4Gi volumes, server image tag `1.19` | `Gitea` `gitea-server` (`pfe.rhpds.com/v1`): image `quay.io/rhpds/gitea:1.27.3`, SSL route, admin `gitea-admin` from secret, registration disabled | plat |
| `Nexus` `nexus` (`gpte.opentlc.com/v1alpha1`) in `opentlc-shared` | image `3.18.1-01-ubi-3`, 5Gi, proxies `maven-central`, `redhat-ga`, `jboss`, hosted `releases`, group `maven-all-public` | Deployment/Service/PVC `nexus` in `nexus` (`sonatype/nexus3:3.96.3`, 10Gi) + config Job (same proxies and group; the unused hosted `releases` repo is dropped) | plat |
| `TektonConfig` `config` | created by the Pipelines operator | created by the operator (not managed) | - |
| Templates `postgresql-ephemeral`, `mariadb-ephemeral` (openshift ns, OpenShift samples) | used by the guide; create **DeploymentConfigs** on 4.22 | `coolstore-postgresql`, `coolstore-mariadb` Templates in `openshift` (Deployments, PostgreSQL 15, MariaDB 10.5) | plat |
| ImageStream `openshift/java` | had `openjdk-21-ubi8` on 4.20/4.21 | tag `openjdk-21-ubi9` added by the `cluster-integration` Job | plat |

## 3. Namespaces and per-user resources

| Item | Old | New | Where |
|---|---|---|---|
| Staging project | `cn-project<N>` with labels `argocd.argoproj.io/managed-by: argocd`, `istio-discovery: enabled` | `cn-project-<user>` with the same labels | users |
| Dev project | `my-project<N>`, created by the participant (`oc new-project`) | `my-project-<user>`, pre-created (D9) | users |
| Dev Spaces namespace | `user<N>devspaces` (labels `app.kubernetes.io/part-of: che.eclipse.org`, `component: workspaces-namespace`, annotation `che.eclipse.org/username`) | `devspaces-<user>` with the same labels/annotation | users |
| RoleBindings | `user<N>-project` → `edit` in cn-project; `user<N>-default`: SA `default` → `view` in cn-project; Role/RoleBinding `argocd-manager` for the argocd SAs | `<user>-edit` → `edit` and `default-view` in cn-project; `<user>-admin` → `admin` in my-project and devspaces; the `managed-by` label lets the GitOps operator grant the participant Argo CD access (explicit `argocd-manager` role dropped) | users |
| Mesh access | RoleBinding `kiali-write` → ClusterRole `kiali-write-privileges` (does not exist with the current Kiali operator) | **dropped**: `edit` already allows the Istio resources and workload edits Kiali performs on the user's behalf | - |
| Monitoring | PodMonitor `proxies-monitor` in every cn-project | PodMonitor `istio-proxies-monitor` in `cn-project-<user>` | users |
| Quotas / LimitRanges | none | none (D9); sizing documented in the README | - |
| Service accounts | `pipeline` SA from the Pipelines operator | same (operator) | - |
| Secrets | none per user; Argo CD passwords in `argocd-secret` | `argocd-env-secret` (cn-project), `workshop-credentials` and `workshop-git-credentials` (devspaces ns), created by the `user-setup` Job; bootstrap secrets `workshop-user-password`, `gitea-admin-password` in `gitea` | users, boot |
| DevWorkspace | `wksp-end-to-end-dev`, started, built by parsing the devfile from GitHub at reconcile time, `routingClass: che`, `storage-type: common`, SCC `container-build` | `wksp-end-to-end-dev` with `parent.uri` = raw devfile of the new code repo, `per-user` storage, no container-build SCC, start toggle `prestartWorkspaces` | users |
| DevWorkspaceTemplate | `che-code-workspace` (hand-written che-code editor with `code-rhel8`/`udi-rhel8`) | `che-code-wksp-end-to-end-dev` from the Dev Spaces 3.30 editor definition | users |
| ConfigMaps in the Dev Spaces ns | `settings-xml` (Maven mirror, mounted at `~/.m2`), `gitconfig` (name/email) | `workshop-env` (env vars incl. Git identity); the mirror settings moved into the tooling image | users |
| Gitea users | `user<N>` created through the `/user/sign_up` form with the workshop password | `<user>` created via the admin API by the `user-setup` Job | users |
| Gitea repositories | created by participants or scripts (`inventory-quarkus`, `inventory-gitops`, `catalog-gitops`, `gateway-gitops`, `web-gitops`) | unchanged (participants/scripts) | - |
| Argo CD projects and access | AppProject + RBAC lines + local account per user | AppProject + RBAC lines + apiKey-only account per user | users, plat |

## 4. Shared services, routes and images

| Service | Old endpoint | New endpoint |
|---|---|---|
| Gitea | `gitea-server.gitea.svc:3000`, route `gitea-server-gitea.<apps>` | unchanged |
| Nexus | `nexus.opentlc-shared.svc:8081/repository/maven-all-public` | `nexus.nexus.svc:8081/repository/maven-all-public/` |
| Argo CD (participants) | route `argocd-server-argocd.<apps>`, `argocd-server.argocd.svc` | unchanged |
| Kiali | route `kiali-istio-system.<apps>` | unchanged |
| Dev Spaces | `devspaces.<apps>` | unchanged |
| Portal | `username-distribution` + Redis in `workshop-infra`, route to assign `userN` and link the guides with query parameters (`APPS_HOSTNAME_SUFFIX`, `USER_ID`, `OPENSHIFT_PASSWORD`, `WORKSHOP_GIT_REPO`, `WORKSHOP_GIT_REF`), fixed admin password | **dropped** (decision 8): `lab-guide-url-template` ConfigMap + `print-user-urls.sh` |
| Bookbag | per-user bookbag deployments (only if `guide.bookbag.enabled`; disabled in the sample) | **dropped** |
| Lab guides | GitHub Pages of the old Inner and Outer Loop guide repositories (MIGRATION.md, section 1) (Antora, course-ui bundle), placeholders replaced client-side from the portal's query string | one Antora site `quay.io/mostmark/inner-outer-loop-lab:latest` served in `lab-guide` (route `doc`), URL parameters `OPENSHIFT_USERNAME`, `OPENSHIFT_PASSWORD`, `OPENSHIFT_CONSOLE_URL`, `OPENSHIFT_API_URL` |

Images used by the old setup: `workshop-tools:6.9` of the old organisation (workspace;
rebuilt as `quay.io/mostmark/workshop-tools:latest`, D14),
`username-distribution:latest` and Redis (portal, dropped),
`quay.io/gpte-devops-automation/gitea-operator:v1.2.3` (replaced), 
`nexus-operator:v0.10` (replaced), `registry.redhat.io/devspaces/code-rhel8`,
`udi-rhel8` (replaced by the 3.30 editor images), `quay.io/argoproj/argocd:v2.2.2` in the guide's
Task (now `v3.4.7`), `golang:1.12`/`alpine:3.9` for catalog v2 (now UBI 9 go-toolset).

Authentication: the old operator targeted RHPDS clusters with htpasswd users `user1..userN`
(`htpasswd/` scripts with a fixed default password). The new setup assumes the users already exist in any
identity provider (the test cluster uses Keycloak/OpenID) and takes their password from
`WORKSHOP_USER_PASSWORD`; `htpasswd/` is not carried over.

## 5. Guide and devfile references

Summary; the complete per-page lists (line numbers, contexts) are in the appendices.

| Kind | Found | New |
|---|---|---|
| Placeholders | `%USER_ID%`, `%APPS_HOSTNAME_SUFFIX%`, `%OPENSHIFT_PASSWORD%`, `%WORKSHOP_GIT_REPO%`, `%WORKSHOP_GIT_REF%`, page-level attributes `OPENSHIFT_CONSOLE_URL` (full topology URL), `CHE_URL`, `KIALI_URL`, `GITEA_URL`, `ARGOCD_URL`, `JAEGER_URL`, `{USER_ID}` in 8 naming patterns | `{OPENSHIFT_USERNAME}`, `{OPENSHIFT_PASSWORD}`, `{OPENSHIFT_CONSOLE_URL}` (host), `{OPENSHIFT_API_URL}`, derived `{OPENSHIFT_APPS_DOMAIN}`; shared attributes in `partials/_attributes.adoc` |
| Hostnames | `devspaces.<apps>`, `*-my-project<N>.<apps>`, `*-cn-project<N>.<apps>`, `istio-ingressgateway-cn-project<N>.<apps>`, `gitea-server-gitea`, `argocd-server-argocd`, `kiali-istio-system`, console topology links | same routes with `-<user>` names |
| Service DNS | `gitea-server.gitea.svc:3000`, `nexus.opentlc-shared.svc:8081`, `argocd-server.argocd.svc`, `*-coolstore.my-project<N>.svc:8080`, DBs in my-project | same, Nexus in `nexus` |
| External URLs | the old example code repository (devfile, factory links, `oc new-app` sources, `completed` branch), the old guide sites and course-ui bundle, docs pinned to OCP 4.19, OpenTLC hostnames in sample output | `mostmark/inner-outer-loop-workshop-code` on `main`; Showroom UI bundle; OCP 4.22 docs |
| Assumed resources | pre-created and started workspace, Gitea with accounts, Nexus mirror, Argo CD instance with accounts and AppProject, Pipelines console plugin, `openshift/java` Java 21 tag, database templates, OSSM 3 control plane, Kiali, user workload monitoring, `cn-project` in the mesh | all provisioned by the charts (sections 2 and 3) |

## 6. Mapping summary

| Old item | New place |
|---|---|
| Workshop CR `spec.user.number` | `users.count` / `users.prefix` / `users.explicitNames` (root Application parameters) |
| Operator subscriptions + InstallPlan approval | ops chart (Subscriptions, Kiali approval Job, readiness Job) |
| Dev Spaces, Service Mesh, Kiali, monitoring, Argo CD, Gitea, Nexus instances | plat chart |
| Per-user namespaces, RBAC, workspaces, AppProjects, Gitea accounts | users chart |
| Portal, Redis, bookbag | dropped (URL template ConfigMap + `print-user-urls.sh`) |
| Guides on GitHub Pages | lab-guide chart + `inner-outer-loop-workshop` image |
| htpasswd helper scripts | dropped (users pre-exist) |
| `remove-devspaces.sh` | `cleanup.sh` (GitOps cleanup plus OLM leftovers) |
| Serverless, Jaeger, Elasticsearch, Istio Workspace, ztunnel namespace, `kiali-write` binding, Nexus `releases` repo | dropped (unused) |
