# Final report

Migration of the Inner & Outer Loop workshop from the `workshop-operator` to OpenShift GitOps,
verified on the test cluster `https://api.cluster-khd65.dyn.redhatworkshops.io:6443`
(OpenShift 4.22.14, one node with 32 vCPU / 128 GiB, x86_64) with 3 users (`user1`..`user3`).
Smoke-test output below is complete and verbatim; bootstrap and cleanup output is an excerpt
(their progress log lines and final status), omitting the `oc apply`/`oc delete` lines.

## Definition of Done

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Repos populated and pushed, no forbidden references, only `main` | Done | section 1 |
| 2 | Every page migrated and mapped, deprecated features updated, clean Antora build | Done | section 2, [MIGRATION.md](MIGRATION.md) section 3 |
| 3 | Lab guide image built, pushed, anonymously pullable, deployed by the chart | Done | section 3 |
| 4 | `bootstrap.sh` alone provisions the workshop; all Applications Synced and Healthy | Done | section 4 |
| 5 | `platform-check.sh` (3 users), `user-journey.sh user1`, `isolation-check.sh` pass | Done | section 5 |
| 6 | Cleanup removes the workshop; a second bootstrap from scratch succeeds | Done | section 4 (one-pass cleanup with participant content, then bootstrap from scratch) |
| 7 | `helm lint` and `helm template` pass for all value variants | Done | section 6 |
| 8 | Documentation | Done | section 8 |

## 1. Repositories

| Repository | Content | Branches |
|---|---|---|
| `github.com/mostmark/inner-outer-loop-workshop` | Antora lab guide, `SCREENSHOTS-TODO.md`, Pages preview `https://mostmark.github.io/inner-outer-loop-workshop/` | `main` only |
| `github.com/mostmark/inner-outer-loop-workshop-gitops` | charts, `argocd/`, `bootstrap.sh`, `cleanup.sh`, `print-user-urls.sh`, `smoke-tests/`, `migration/` | `main` only |
| `github.com/mostmark/inner-outer-loop-workshop-code` | code, devfile, `.tasks`, pipelines, `tools/` (tooling image) | `main` only |

Checks run on the final state (all empty):

```text
$ grep -rE "[%][A-Z_]+%" inner-outer-loop-workshop inner-outer-loop-workshop-code
matches: 0
$ grep -rniE "[R]edHat-EMEA-SSA-Team|[r]edhat-scholars" <all three repos> | grep -v migration/MIGRATION.md
matches: 0
$ grep -rniE "[o]pentlc|[u]sername-distribution|[w]orkshop-infra" <content, code, gitops charts/scripts/argocd/smoke-tests>
matches: 0
$ grep -rnE "([t]argetRevision|[r]evision): *[0-9]|github[.]com/[^ ]*/(blob|tree)/[0-9]|/[6][.][0-9]+/|#[6][.][0-9]" <all three repos, excluding migration/>
matches: 0
$ grep -rhn "targetRevision" argocd/ charts/workshop/values.yaml
12:    targetRevision: main
26:        - name: source.targetRevision
8:# Git source of the component charts. bootstrap.sh overrides repoURL/targetRevision when needed.
11:  targetRevision: main
$ git ls-remote --heads --tags (each repo)
inner-outer-loop-workshop: refs/heads/main 
inner-outer-loop-workshop-gitops: refs/heads/main 
inner-outer-loop-workshop-code: refs/heads/main
```

## 2. Lab guide content

- 16 source pages (9 Inner Loop incl. `index.adoc`, 7 Outer Loop incl. `index.adoc`) became 15
  pages in one component with two navigation parts; the mapping is in MIGRATION.md section 3.
- Antora 3.1.12 build with `--log-failure-level=warn`: exit 0, no warnings (no broken xrefs, no
  missing images, no unresolved attributes).
- Deprecated features updated: DeploymentConfig (database templates, JKube, export), Tekton
  `v1beta1` and PipelineResources, OSSM 2 concepts and Jaeger, `networking.istio.io/v1beta1`,
  "Developer/Administrator perspective", Argo CD 2 UI and password login, `master` branches.

## 3. Images

```text
$ skopeo inspect --no-creds docker://quay.io/mostmark/inner-outer-loop-lab:latest
manifest list: amd64, arm64
$ skopeo inspect --no-creds docker://quay.io/mostmark/workshop-tools:latest
single manifest
$ oc get deploy lab-guide -n lab-guide (image)
quay.io/mostmark/inner-outer-loop-lab:latest
```

The lab guide Deployment runs this image (`quay.io/mostmark/inner-outer-loop-lab:latest`,
`imagePullPolicy: Always`), and `platform-check.sh` fetches all 15 pages from its route.

## 4. Provisioning, cleanup and bootstrap from scratch

The workshop was bootstrapped four times on the test cluster; every bootstrap after the first ran
on a cluster cleaned by `cleanup.sh` and needed no other step than `./bootstrap.sh --users 3`.
The cleanup script was hardened between the runs (see "Cleanup history" below); the evidence here
is from the final scripts:

1. bootstrap #3 from scratch, then `user-journey.sh user1` (so participant content exists),
2. one-pass `./cleanup.sh --yes` of that complete installation, which ends by verifying that no
   workshop namespace, operator, CRD, webhook or cluster addition is left (non-zero exit otherwise),
3. bootstrap #4 from scratch, then the platform and isolation checks of section 5.

Bootstrap #3 (from a cleaned cluster):

```text
[06:27:21] Logged in as: admin
[06:27:21] Server:       https://api.cluster-khd65.dyn.redhatworkshops.io:6443
[06:27:21] Users:        user1..user3
[06:27:21] Source:       https://github.com/mostmark/inner-outer-loop-workshop-gitops.git@main
[06:27:21] Installing the OpenShift GitOps operator (channel gitops-1.21)
[06:27:46] OpenShift GitOps operator: ready
[06:28:17] Argo CD instance openshift-gitops: ready
[06:28:17] Granting cluster-admin to the openshift-gitops application controller
[06:28:17] Configuring the Application health check on the openshift-gitops Argo CD instance
[06:28:18] Creating secrets in the gitea namespace
[06:28:21] Applying the root Application inner-outer-loop-workshop
[06:28:21] Waiting up to 3600s for all Applications to be Synced and Healthy
[06:28:23] inner-outer-loop-workshop=<none>/<none> 
[06:28:45] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Progressing 
[06:29:52] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Degraded 
[06:30:15] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Progressing 
[06:30:59] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy 
[06:32:06] inner-outer-loop-workshop=OutOfSync/Healthy workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Healthy 
[06:32:29] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Progressing 
[06:33:59] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Healthy 
[06:34:44] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Progressing 
[06:35:29] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy 
[06:36:15] inner-outer-loop-workshop=OutOfSync/Healthy workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy workshop-users=OutOfSync/Missing 
[06:36:37] inner-outer-loop-workshop=Synced/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy workshop-users=OutOfSync/Healthy 
[06:37:23] inner-outer-loop-workshop=Synced/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy workshop-users=Synced/Healthy 
[06:37:45] All Applications are Synced and Healthy
real	10m26.650s
bootstrap exit=0
```

State before the cleanup (participant content of user1 deployed by the journey):

```text
== before cleanup: Applications (openshift-gitops, argocd)
argocd             catalog-user1               Synced   Healthy
argocd             gateway-user1               Synced   Healthy
argocd             inventory-user1             Synced   Healthy
argocd             web-user1                   Synced   Healthy
openshift-gitops   inner-outer-loop-workshop   Synced   Healthy
openshift-gitops   workshop-lab-guide          Synced   Healthy
openshift-gitops   workshop-operators          Synced   Healthy
openshift-gitops   workshop-platform           Synced   Healthy
openshift-gitops   workshop-users              Synced   Healthy
== user1 Deployments
catalog-coolstore     1/1   1     1     14m
catalog-postgresql    1/1   1     1     11m
gateway-coolstore     1/1   1     1     14m
inventory-coolstore   1/1   1     1     16m
inventory-mariadb     1/1   1     1     11m
web-coolstore         1/1   1     1     13m
catalog-coolstore      1/1   1     1     4m38s
catalog-coolstore-v2   1/1   1     1     2m56s
gateway-coolstore      1/1   1     1     4m41s
inventory-coolstore    1/1   1     1     6m50s
istio-ingressgateway   1/1   1     1     2m59s
web-coolstore          1/1   1     1     3m38s
```

One-pass cleanup of the complete installation:

```text
[06:58:45] Logged in as: admin
[06:58:45] Server:       https://api.cluster-khd65.dyn.redhatworkshops.io:6443
[06:58:46] Deleting the root Application inner-outer-loop-workshop (Argo CD prunes everything it manages)
[07:01:12] workshop Applications: gone
[07:01:16] workshop namespaces: gone
[07:01:16] Removing TektonConfig (lets the Pipelines operator clean up openshift-pipelines)
[07:01:54] TektonConfig installer sets: gone
[07:01:54] Removing operator Subscriptions and ClusterServiceVersions
[07:02:11] Operator for tektoninstallersets.operator.tekton.dev is gone; removing finalizers of <none>/validating-mutating-webhook-gwgzm
[07:02:13] Pipelines operator installer sets: gone
[07:02:13] Removing operator namespaces kept during the Argo CD cleanup
[07:02:13] Removing objects the operators created themselves
[07:02:22] Disabled console plugin pipelines-console-plugin
[07:02:31] Removed openshift/java:openjdk-21-ubi9
[07:02:31] Removing the operators' CRDs
[07:02:41] Removing OpenShift GitOps
[07:03:19] Argo CD instances: gone
[07:03:35] operator namespaces: gone
Workshop cleanup complete; verified that no workshop namespaces, operators, CRDs,
webhooks or cluster additions are left.
real	4m59.993s
cleanup exit=0
```

State after the cleanup (only the platform's own add-ons remain: ODF, cert-manager, Keycloak):

```text
== namespaces (non-platform)
assisted-installer
cert-manager
cert-manager-operator
keycloak
== CSVs
cephcsi-operator.v4.21.12-rhodf
cert-manager-operator.v1.20.0
mcg-operator.v4.21.12-rhodf
ocs-client-operator.v4.21.12-rhodf
ocs-operator.v4.21.12-rhodf
odf-csi-addons-operator.v4.21.12-rhodf
odf-dependencies.v4.21.12-rhodf
odf-external-snapshotter-operator.v4.21.12-rhodf
odf-operator.v4.21.12-rhodf
odf-prometheus-operator.v4.21.12-rhodf
packageserver
recipe.v4.21.12-rhodf
rhbk-operator.v26.4.16-opr.1
rook-ceph-operator.v4.21.12-rhodf
```

Kept by design: the pre-created users (identity provider), `openshift-user-workload-monitoring`
(owned by the cluster monitoring operator).

Bootstrap #4 (from the cleaned cluster, the installation left running):

```text
[07:03:47] Logged in as: admin
[07:03:47] Server:       https://api.cluster-khd65.dyn.redhatworkshops.io:6443
[07:03:47] Users:        user1..user3
[07:03:47] Source:       https://github.com/mostmark/inner-outer-loop-workshop-gitops.git@main
[07:03:47] Installing the OpenShift GitOps operator (channel gitops-1.21)
[07:04:12] OpenShift GitOps operator: ready
[07:04:46] Argo CD instance openshift-gitops: ready
[07:04:46] Granting cluster-admin to the openshift-gitops application controller
[07:04:46] Configuring the Application health check on the openshift-gitops Argo CD instance
[07:04:47] Creating secrets in the gitea namespace
[07:04:50] Applying the root Application inner-outer-loop-workshop
[07:04:50] Waiting up to 3600s for all Applications to be Synced and Healthy
[07:04:52] inner-outer-loop-workshop=<none>/<none> 
[07:05:15] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Progressing 
[07:06:44] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy 
[07:07:07] inner-outer-loop-workshop=OutOfSync/Healthy workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=<none>/<none> 
[07:07:29] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Healthy 
[07:08:15] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Progressing 
[07:09:22] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Healthy 
[07:11:15] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=OutOfSync/Progressing 
[07:12:00] inner-outer-loop-workshop=OutOfSync/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy 
[07:12:45] inner-outer-loop-workshop=OutOfSync/Healthy workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy workshop-users=<none>/<none> 
[07:13:08] inner-outer-loop-workshop=Synced/Progressing workshop-lab-guide=Synced/Healthy workshop-operators=Synced/Healthy workshop-platform=Synced/Healthy workshop-users=OutOfSync/Healthy 
[07:13:53] All Applications are Synced and Healthy
real	10m8.388s
bootstrap exit=0
```

Cleanup history: the first cleanup run exposed that the GitOps operator re-creates its default
Argo CD instance while it is being uninstalled, and that the Pipelines operator must stay until it
has removed the TektonInstallerSets of TektonConfig (its own webhook installer set lives as long as
the operator). The script now disables the default instance before removing GitOps, waits for the
TektonConfig installer sets, deletes and (if the operator is already gone) de-finalizes leftover
operator objects, removes the ConsolePlugins, the pipelines SCC, Tekton operator webhooks and
operator ClusterRoles the operators create at run time, and verifies the end state.

## 5. Smoke tests

### platform-check.sh, 3 users, final installation (bootstrap #4) (Summary: 112 passed, 0 failed)

```text

=== Argo CD Applications ===
PASS  Application inner-outer-loop-workshop is Synced/Healthy
PASS  Application workshop-operators is Synced/Healthy
PASS  Application workshop-platform is Synced/Healthy
PASS  Application workshop-users is Synced/Healthy
PASS  Application workshop-lab-guide is Synced/Healthy

=== Operators ===
PASS  CSV of openshift-gitops-operator (openshift-gitops-operator.v1.21.4) Succeeded
PASS  CSV of devspaces (devspacesoperator.v3.30.1) Succeeded
PASS  CSV of openshift-pipelines-operator-rh (openshift-pipelines-operator-rh.v1.24.0) Succeeded
PASS  CSV of servicemeshoperator3 (servicemeshoperator3.v3.4.2) Succeeded
PASS  CSV of kiali-ossm (kiali-operator.v2.27.4) Succeeded
PASS  CSV of gitea-operator (gitea-operator.v2.3.2) Succeeded
PASS  DevWorkspace operator CSV Succeeded

=== Operands ===
PASS  CheCluster devspaces is Active
PASS  Istio default is Ready
PASS  IstioCNI default is Ready
PASS  Kiali deployment available
PASS  OSSMConsole plugin deployed
PASS  TektonConfig config is Ready
PASS  Participant Argo CD is Available
PASS  Gitea admin set up
PASS  Gitea deployment available
PASS  Nexus deployment available
PASS  User workload monitoring enabled
PASS  Pipelines console plugin enabled
PASS  Java 21 builder tag openshift/java:openjdk-21-ubi9
PASS  Database templates in openshift

=== Routes ===
PASS  Lab guide (https://doc-lab-guide.apps.cluster-khd65.dyn.redhatworkshops.io/ -> 200)
PASS  Dev Spaces dashboard (https://devspaces.apps.cluster-khd65.dyn.redhatworkshops.io/ -> 200)
PASS  Gitea (https://gitea-server-gitea.apps.cluster-khd65.dyn.redhatworkshops.io/api/v1/version -> 200)
PASS  Argo CD (participants) (https://argocd-server-argocd.apps.cluster-khd65.dyn.redhatworkshops.io/healthz -> 200)
PASS  Argo CD login page (https://argocd-server-argocd.apps.cluster-khd65.dyn.redhatworkshops.io/auth/login -> 303)
PASS  Kiali (https://kiali-istio-system.apps.cluster-khd65.dyn.redhatworkshops.io/ -> 200)
PASS  Nexus Maven group readable anonymously

=== Per-user resources ===
PASS  user1: namespace my-project-user1
PASS  user1: namespace cn-project-user1
PASS  user1: namespace devspaces-user1
PASS  user1: admin in my-project-user1
PASS  user1: edit in cn-project-user1
PASS  user1: cn-project in the mesh
PASS  user1: cn-project managed by participant Argo CD
PASS  user1: AppProject cn-project-user1
PASS  user1: Argo CD token secret
PASS  user1: workspace credentials
PASS  user1: PodMonitor for Istio proxies
PASS  user1: Gitea account
PASS  user1: workspace wksp-end-to-end-dev Running
PASS  user2: namespace my-project-user2
PASS  user2: namespace cn-project-user2
PASS  user2: namespace devspaces-user2
PASS  user2: admin in my-project-user2
PASS  user2: edit in cn-project-user2
PASS  user2: cn-project in the mesh
PASS  user2: cn-project managed by participant Argo CD
PASS  user2: AppProject cn-project-user2
PASS  user2: Argo CD token secret
PASS  user2: workspace credentials
PASS  user2: PodMonitor for Istio proxies
PASS  user2: Gitea account
PASS  user2: workspace wksp-end-to-end-dev Running
PASS  user3: namespace my-project-user3
PASS  user3: namespace cn-project-user3
PASS  user3: namespace devspaces-user3
PASS  user3: admin in my-project-user3
PASS  user3: edit in cn-project-user3
PASS  user3: cn-project in the mesh
PASS  user3: cn-project managed by participant Argo CD
PASS  user3: AppProject cn-project-user3
PASS  user3: Argo CD token secret
PASS  user3: workspace credentials
PASS  user3: PodMonitor for Istio proxies
PASS  user3: Gitea account
PASS  user3: workspace wksp-end-to-end-dev Running

=== Lab guide ===
PASS  URL template ConfigMap
PASS  Start page (https://doc-lab-guide.apps.cluster-khd65.dyn.redhatworkshops.io/modules/index.html -> 200)
PASS  print-user-urls.sh prints a URL for user1
PASS  Per-user URL renders
PASS  Page index served
PASS  Page inner-loop-01-introduction served
PASS  Page inner-loop-02-developer-workspace served
PASS  Page inner-loop-03-inventory-quarkus served
PASS  Page inner-loop-04-catalog-spring-boot served
PASS  Page inner-loop-05-gateway-dotnet served
PASS  Page inner-loop-06-webui-deployment served
PASS  Page inner-loop-07-app-health served
PASS  Page inner-loop-08-app-config served
PASS  Page outer-loop-01-introduction served
PASS  Page outer-loop-02-developer-workspace served
PASS  Page outer-loop-03-continuous-integration served
PASS  Page outer-loop-04-gitops-workflow served
PASS  Page outer-loop-05-continuous-delivery served
PASS  Page outer-loop-06-service-mesh served
PASS  Pages carry the per-user tokens
PASS  Head script derives the apps domain

=== Pods ===
PASS  No crash-looping pods in lab-guide
PASS  No crash-looping pods in workshop-setup
PASS  No crash-looping pods in openshift-devspaces
PASS  No crash-looping pods in istio-system
PASS  No crash-looping pods in istio-cni
PASS  No crash-looping pods in argocd
PASS  No crash-looping pods in gitea
PASS  No crash-looping pods in nexus
PASS  No crash-looping pods in kiali-operator
PASS  No crash-looping pods in gitea-operator
PASS  No crash-looping pods in my-project-user1
PASS  No crash-looping pods in cn-project-user1
PASS  No crash-looping pods in devspaces-user1
PASS  No crash-looping pods in my-project-user2
PASS  No crash-looping pods in cn-project-user2
PASS  No crash-looping pods in devspaces-user2
PASS  No crash-looping pods in my-project-user3
PASS  No crash-looping pods in cn-project-user3
PASS  No crash-looping pods in devspaces-user3

=== Summary: 112 passed, 0 failed ===
platform exit=0
```

### isolation-check.sh user1 user2, final installation (bootstrap #4) (Summary: 44 passed, 0 failed)

```text

=== Log in ===
PASS  Log in as user1
PASS  Log in as user2

=== OpenShift: user1 vs namespaces of user2 ===
PASS  user1 sees only their own projects
PASS  user1 cannot list namespaces cluster-wide
PASS  user1 cannot list pods in my-project-user2
PASS  user1 cannot read secrets in my-project-user2
PASS  user1 cannot create a ConfigMap in my-project-user2
PASS  user1 cannot delete the namespace my-project-user2
PASS  user1 cannot list pods in cn-project-user2
PASS  user1 cannot read secrets in cn-project-user2
PASS  user1 cannot create a ConfigMap in cn-project-user2
PASS  user1 cannot delete the namespace cn-project-user2
PASS  user1 cannot list pods in devspaces-user2
PASS  user1 cannot read secrets in devspaces-user2
PASS  user1 cannot create a ConfigMap in devspaces-user2
PASS  user1 cannot delete the namespace devspaces-user2
PASS  user1 cannot exec into user2's workspace
PASS  user1 cannot read the Argo CD admin secret
PASS  user1 cannot read the Gitea bootstrap secrets
PASS  user1 cannot change the mesh control plane

=== Argo CD (participant instance): user1 vs user2 ===
PASS  user1 can read their own Argo CD token
PASS  user1 cannot read user2's Argo CD token
PASS  user1 can create an Application in their own project
PASS  user2 can create an Application in their own project
PASS  user1 cannot see user2's Application
PASS  user1's Application list has no user2 project
PASS  user1 cannot create an Application in user2's project
PASS  user1's project cannot deploy into user2's namespace
PASS  user1 cannot sync user2's Application
PASS  user1 cannot delete user2's Application

=== Argo CD SSO (LOG IN VIA OPENSHIFT): user1 vs user2 ===
PASS  user1 logs in to Argo CD through OpenShift
PASS  user1's SSO session is mapped to user user1
PASS  user1 (SSO) can read their own project
PASS  user1 (SSO) cannot read user2's project
PASS  user1 (SSO) cannot create an Application in user2's project
PASS  user1 (SSO) sees no Applications in the admin-only openshift-gitops instance
PASS  user1 (SSO) cannot read the root Application in openshift-gitops

=== Gitea: user1 vs repositories of user2 ===
PASS  user2 owns repository isolation-probe
PASS  user1 cannot write to user2's repository
PASS  user1 cannot delete user2's repository
PASS  user1 cannot change user2's repository settings
PASS  user1 cannot use the admin API
PASS  user1 cannot push over git to user2's repository

=== Kiali ===
PASS  user1's Kiali view does not include user2's namespaces

=== Summary: 44 passed, 0 failed ===
isolation exit=0
```

### user-journey.sh user1 on a fresh installation (bootstrap #3) (Summary: 76 passed, 0 failed)

Strict mode (stops at the first failure), both parts, run inside user1's workspace:

```text

=== Log in as user1 ===
PASS  oc login as user1 with the workshop password
PASS  oc whoami is user1
PASS  Workspace wksp-end-to-end-dev is Running
PASS  Workspace pod found (workspace182d37476d3d4c30-fb856c444-mv456)
PASS  Workspace sources are up to date with main

=== Part 1 - Inner Loop ===
PASS  Devfile 'OpenShift - Login'
PASS  Workspace oc session is user1
PASS  Devfile 'OpenShift - Create Development Project'
PASS  Workspace current project is my-project-user1
PASS  Inventory: add the solution code
PASS  Inventory: devfile 'Inventory - Deploy Component'
PASS  Inventory: rollout
PASS  Inventory: route answers /api/inventory/329299
PASS  Catalog: add the solution code
PASS  Catalog: devfile 'Catalog - Deploy Component'
PASS  Catalog: rollout
PASS  Catalog: route answers /api/catalog
PASS  Gateway: devfile 'Gateway - Build and Deploy Component'
PASS  Gateway: rollout
PASS  Gateway: route answers /api/products
PASS  Web UI: import from Git (Node.js builder)
PASS  Web UI: build and rollout
PASS  Web UI: route answers
PASS  Health: probes for all four services
PASS  Health: inventory-coolstore has a readiness probe
PASS  Health: inventory-coolstore rolled out
PASS  Health: catalog-coolstore has a readiness probe
PASS  Health: catalog-coolstore rolled out
PASS  Health: gateway-coolstore has a readiness probe
PASS  Health: gateway-coolstore rolled out
PASS  Health: web-coolstore has a readiness probe
PASS  Health: web-coolstore rolled out
PASS  Health: inventory readiness endpoint
PASS  Configuration: databases and ConfigMaps
PASS  Configuration: inventory-mariadb is a Deployment and ready
PASS  Configuration: catalog-postgresql is a Deployment and ready
PASS  Configuration: inventory rolled out
PASS  Configuration: catalog rolled out
PASS  Configuration: inventory uses MariaDB
PASS  Configuration: inventory still serves data
PASS  Configuration: catalog still serves data
PASS  Configuration: web UI through the gateway

=== Part 2 - Outer Loop ===
PASS  CI: push inventory to Gitea and create the pipeline
PASS  CI: repository user1/inventory-quarkus has a main branch
PASS  CI: PipelineRun started (inventory-pipeline-75wm4)
PASS  CI: PipelineRun inventory-pipeline-75wm4 succeeded (git-clone, s2i-java)
PASS  CI: image inventory-coolstore in cn-project-user1
PASS  GitOps: export and push the configuration, create the Argo CD Applications
PASS  GitOps: repository user1/inventory-gitops has the manifests
PASS  GitOps: no DeploymentConfig in the export
PASS  GitOps: Application inventory-user1 in the participant Argo CD
PASS  GitOps: sync inventory-user1 (as in the Argo CD UI)
PASS  GitOps: inventory rolled out in cn-project-user1
PASS  CD: Argo CD Task, ConfigMap and extended pipeline
PASS  CD: run the CD pipelines of all services
PASS  CD: inventory PipelineRun with Argo CD sync succeeded
PASS  CD: Argo CD Application inventory-user1 Synced and Healthy
PASS  CD: Argo CD Application catalog-user1 Synced and Healthy
PASS  CD: Argo CD Application gateway-user1 Synced and Healthy
PASS  CD: Argo CD Application web-user1 Synced and Healthy
PASS  CD: inventory-coolstore rolled out in cn-project-user1
PASS  CD: catalog-coolstore rolled out in cn-project-user1
PASS  CD: gateway-coolstore rolled out in cn-project-user1
PASS  CD: web-coolstore rolled out in cn-project-user1
PASS  CD: gateway in cn-project-user1 answers
PASS  Mesh: sidecar injection, per-user ingress gateway, Gateway/VirtualServices
PASS  Mesh: inventory-coolstore rolled out with a sidecar (2/2)
PASS  Mesh: catalog-coolstore rolled out with a sidecar (2/2)
PASS  Mesh: gateway-coolstore rolled out with a sidecar (2/2)
PASS  Mesh: ingress gateway rolled out
PASS  Mesh: products through the Istio ingress gateway
PASS  Mesh: devfile 'Gateway - Generate Traffic' (90 s)
PASS  Mesh: Kiali shows traffic in cn-project-user1 (graph has edges)
PASS  Mesh: Kiali graph has istio-ingressgateway -> gateway-coolstore
PASS  Mesh: Kiali graph has gateway-coolstore -> inventory-coolstore
PASS  Mesh: Kiali graph has gateway-coolstore -> catalog-coolstore

=== Summary: 76 passed, 0 failed ===
journey exit=0
```

The same journey also passed 76/76 on bootstrap #2. Earlier runs found and fixed: the export kept
Quarkus' `resolve-names` annotation (Argo CD drift, fixed in the code repo), the project cleanup
deleted PVCs before pipeline runs (deadlock, fixed), plus four test-script defects.
`user-journey.sh user1 --reset` returns user1 to the initial state (11 checks passed).

## 6. Helm

```text
lab-guide [defaults] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
lab-guide [--set users.count=30] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
lab-guide [--set users.explicitNames={alice,bob}] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
lab-guide [--set users.prefix=student] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop [defaults] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop [--set users.count=30] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop [--set users.explicitNames={alice,bob}] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop [--set users.prefix=student] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-operators [defaults] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-operators [--set users.count=30] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-operators [--set users.explicitNames={alice,bob}] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-operators [--set users.prefix=student] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-platform [defaults] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-platform [--set users.count=30] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-platform [--set users.explicitNames={alice,bob}] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-platform [--set users.prefix=student] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-users [defaults] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-users [--set users.count=30] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-users [--set users.explicitNames={alice,bob}] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
workshop-users [--set users.prefix=student] lint: 1 chart(s) linted, 0 chart(s) failed template: ok
```

## 7. Resource footprint and sizing

Measured with `smoke-tests/footprint.sh` while user1 had both parts deployed and user2 was idle
(pre-started workspace only); user3 was idle like user2 and is omitted:

```text
Scope                          Pods   CPU req    Mem req   CPU lim    Mem lim   CPU use    Mem use
user1 (all)                      13      280m     2368Mi     2500m     6400Mi      137m     3640Mi
  devspaces-user1                 1      280m     1344Mi     2500m     5376Mi        1m      302Mi
  my-project-user1                6        0m     1024Mi        0m     1024Mi       55m     1640Mi
  cn-project-user1                6        0m        0Mi        0m        0Mi       78m     1702Mi
user2 (all)                       1      280m     1344Mi     2500m     5376Mi        2m      256Mi
  devspaces-user2                 1      280m     1344Mi     2500m     5376Mi        2m      256Mi
  my-project-user2                0        0m        0Mi        0m        0Mi        0m        0Mi
  cn-project-user2                0        0m        0Mi        0m        0Mi        0m        0Mi
shared platform                  49     4582m    10766Mi    14000m    29928Mi      296m     7458Mi
operators (openshift-operators)      8      570m      396Mi     4400m     8792Mi       29m      711Mi
```

Per participant: 0.28 vCPU / 2.3 GiB requested, about 3.6 GiB used with both parts deployed
(workspace idle 0.3 GiB, Inner Loop project 1.6 GiB, Outer Loop project 1.7 GiB), plus about 2 GiB
and 1-2 vCPU while Maven builds or pipeline runs are active. Shared platform: 4.6 vCPU / 10.5 GiB
requested, about 7.5 GiB used; operators about 0.7 GiB.

Sizing for 20-30 participants (details and the 3/10/20/30 table in the README):

| Participants | Memory steady / peak | CPU peak | Workers (16 vCPU / 64 GiB) |
|---|---|---|---|
| 20 | 90 GiB / 130 GiB | 40 vCPU | 3 |
| 30 | 130 GiB / 190 GiB | 60 vCPU | 4 |

This matches the old guidance of about 8 participants per 16 vCPU / 64 GiB worker. Memory is the
limiting resource; plan about 13.5 GiB of persistent volume claims per participant (workspace
10 GiB, pipeline PVCs up to 3.5 GiB).

## 8. Documentation

| Document | Where |
|---|---|
| READMEs | root of each repository |
| Migration record (sources and SHAs, component mapping, page mapping, changes) | `migration/MIGRATION.md` |
| Component inventory | `migration/COMPONENT-INVENTORY.md` |
| Decisions | `migration/DECISIONS.md` |
| Known issues | `migration/KNOWN-ISSUES.md` |
| Progress log | `migration/PROGRESS.md` |
| Screenshot recapture list | `SCREENSHOTS-TODO.md` (content repository) |

## 9. Remaining manual work

- **Screenshots**: recapture the images listed in `SCREENSHOTS-TODO.md` (content repository) on an
  OpenShift 4.22 cluster, keeping the file names; P1 images contradict the new text.
- **Event password**: use an event-specific `WORKSHOP_USER_PASSWORD` (KNOWN-ISSUES K17) and make
  sure the users' passwords in the identity provider match it (K12).
- Optional follow-ups from KNOWN-ISSUES: .NET 10 when .NET 9 leaves support, Spring Boot 3 for the
  catalog, Dev Spaces editor image digests after Dev Spaces upgrades.

## 10. Notes on the test environment

- The Keycloak realm on the test cluster had different per-user passwords; with the owner's
  approval they were reset to `WORKSHOP_USER_PASSWORD` for user1..user5.
- The quay.io repositories were created private by the first push; the owner made them public.
- The GitHub token initially lacked the `workflow` scope (fixed by the owner); GitHub Pages was
  then enabled for the content repository.
- The test password is the old workshop's public default and therefore appears in Git history
  (upstream import commit, two early documentation commits). The owner accepted this as
  documented (KNOWN-ISSUES K17) instead of rewriting history; real events use their own password.
- During the migration a subagent created, by mistake, a Pipeline in namespace `default` and
  deleted it about 20 seconds later; nothing else was affected.
