# Inner & Outer Loop Workshop GitOps

The charts prepare an OpenShift cluster for the Inner & Outer Loop workshop (Part 1 Inner Loop,
Part 2 Outer Loop) with OpenShift GitOps. They manage:

- the operators: OpenShift Dev Spaces, OpenShift Pipelines, OpenShift Service Mesh 3, Kiali, Gitea
- the shared platform: Dev Spaces, the Istio control plane, Kiali and its console plugin, user
  workload monitoring, an Argo CD instance for participants, Gitea, a Nexus Maven mirror, database
  templates
- per-user namespaces, role bindings, Dev Spaces workspaces, Argo CD projects, Gitea accounts and
  credentials
- the lab guide: namespace, deployment, service, route and the URL template ConfigMap

The lab guide lives in [inner-outer-loop-workshop](https://github.com/mostmark/inner-outer-loop-workshop)
and the example code in [inner-outer-loop-workshop-code](https://github.com/mostmark/inner-outer-loop-workshop-code).

## Repository Layout

```text
.
├── argocd/
│   └── application.yaml          # root Application (app-of-apps)
├── charts/
│   ├── workshop/                 # renders the four child Applications
│   ├── workshop-operators/       # Subscriptions, OperatorGroups, CatalogSource, readiness Jobs
│   ├── workshop-platform/        # shared instances (Dev Spaces, mesh, Kiali, Argo CD, Gitea, Nexus ...)
│   ├── workshop-users/           # per-user resources
│   └── lab-guide/                # lab guide deployment and URL template
├── bootstrap.sh                  # the only imperative step
├── cleanup.sh                    # removes the workshop
├── print-user-urls.sh            # prints each participant's lab guide URL
├── smoke-tests/                  # platform-check.sh, user-journey.sh, isolation-check.sh
└── migration/                    # migration record, decisions, inventory, known issues, report
```

## Architecture

```text
bootstrap.sh
  ├─ installs OpenShift GitOps (openshift-gitops, admin only) and configures it
  ├─ creates the secrets that must not live in Git (namespace gitea)
  └─ applies argocd/application.yaml
        root Application "inner-outer-loop-workshop"  (charts/workshop)
          ├─ wave 0  workshop-operators   Subscriptions ─► wait-for-operators Job
          ├─ wave 0  workshop-lab-guide   lab guide
          ├─ wave 1  workshop-platform    CheCluster, Istio/IstioCNI, Kiali, OSSMConsole, monitoring,
          │                               ArgoCD "argocd", Gitea, Nexus (+ config Job), DB templates,
          │                               cluster-integration Job ─► wait-for-platform Job
          └─ wave 2  workshop-users       per user: namespaces, RBAC, AppProject, PodMonitor,
                                          workspace env + editor + DevWorkspace ─► user-setup Job
                                          (Gitea accounts, Argo CD tokens, credential Secrets)
```

Each wave starts only when the previous child Application is Synced, Healthy and its sync
(including the readiness Jobs) succeeded: `bootstrap.sh` adds that health check for
`argoproj.io/Application` to the `openshift-gitops` instance.

What participants use:

| Component | Namespace | URL / service |
|---|---|---|
| Lab guide | `lab-guide` | `https://doc-lab-guide.<apps domain>` |
| Dev Spaces | `openshift-devspaces`, workspaces in `devspaces-<user>` | `https://devspaces.<apps domain>` |
| Development project (Part 1) | `my-project-<user>` | |
| Staging project (Part 2) | `cn-project-<user>` (in the mesh, managed by the participant Argo CD) | |
| Gitea | `gitea` | `https://gitea-server-gitea.<apps domain>`, `http://gitea-server.gitea.svc:3000` |
| Argo CD (participants, OpenShift login) | `argocd` | `https://argocd-server-argocd.<apps domain>` |
| Kiali | `istio-system` | `https://kiali-istio-system.<apps domain>` |
| Maven mirror | `nexus` | `http://nexus.nexus.svc:8081/repository/maven-all-public/` |

The `openshift-gitops` instance is admin-only. Participants have no access to it, to `argocd`,
`gitea`, `nexus` or any other participant's namespaces (see `smoke-tests/isolation-check.sh`).

## Prerequisites

- OpenShift 4.22 on x86_64 (the workshop does not support ARM), with a default storage class and
  the internal image registry enabled.
- Cluster-admin access with `oc`.
- The workshop users already exist in the cluster's identity provider and share one password,
  passed as `WORKSHOP_USER_PASSWORD`. The users must be able to log in with `oc login -u -p`.
- No existing `cluster-monitoring-config` ConfigMap in `openshift-monitoring` (Argo CD owns it to
  enable user workload monitoring). If you have one, merge `enableUserWorkload: true` into
  `charts/workshop-platform/templates/monitoring.yaml` first.

## Install

```bash
export WORKSHOP_USER_PASSWORD='<password of the workshop users>'
./bootstrap.sh --users 20
```

`bootstrap.sh` is idempotent. It waits (default up to 60 minutes) until every Application is
Synced and Healthy and prints the lab guide URL template. A fresh install took about 10 minutes
on the test cluster (operators about 4, platform about 4, users about 1), plus 2 to 3 minutes until
the pre-started workspaces are running.

Options: `--users N`, `--prefix PREFIX`, `--names a,b,c`, `--repo URL`, `--revision REV`,
`--timeout SECONDS`, `--no-wait`. `GITOPS_CHANNEL` overrides the OpenShift GitOps channel
(`gitops-1.21`).

What `bootstrap.sh` grants the provisioning instance and why:

- ClusterRoleBinding `inner-outer-loop-workshop-provisioner` (`cluster-admin`) for
  `openshift-gitops-argocd-application-controller`: the charts create namespaces, cluster-scoped
  RBAC, OLM objects in operator namespaces, cluster-scoped operand CRs (Istio, IstioCNI), the
  cluster monitoring ConfigMap, Templates in `openshift`, and RoleBindings that grant participants
  ClusterRoles such as `admin`. Kubernetes only lets a subject grant permissions it holds itself.
- A `resourceHealthChecks` entry for `argoproj.io/Application` on the `openshift-gitops` ArgoCD CR,
  so the root Application's sync waves wait for each layer.

## Configure Users

By default the chart creates 10 users named `user1` through `user10`.

```yaml
users:
  count: 10
  prefix: user
  explicitNames: []
```

The users are set with Helm parameters on the root Application (`argocd/application.yaml`);
`bootstrap.sh` sets them from `--users`, `--prefix` and `--names`:

```yaml
spec:
  source:
    helm:
      parameters:
        - name: users.count
          value: "20"
        - name: users.prefix
          value: user
        - name: users.explicitNames
          value: "null"
```

The `users.explicitNames` parameter uses `"null"` by default because Helm parameters do not
cleanly represent an empty list. To use explicit usernames instead:

```yaml
        - name: users.explicitNames
          value: "{alice,bob,charlie}"
```

When `users.explicitNames` contains one or more names, `users.count` and `users.prefix` are
ignored. The root chart passes the `users` block to every child chart.

To add participants during a workshop, run `bootstrap.sh` again with the new count (or change
the parameter in Argo CD). Removing participants prunes their namespaces.

## Resources Per User

| Namespace | Contents | Participant role |
|---|---|---|
| `my-project-<user>` | Part 1 development project | `admin` |
| `cn-project-<user>` | Part 2 staging project; labels `istio-discovery=enabled`, `argocd.argoproj.io/managed-by=argocd`; PodMonitor for Envoy metrics; Secret `argocd-env-secret` (Argo CD API token) | `edit` |
| `devspaces-<user>` | DevWorkspace `wksp-end-to-end-dev` (started by default), VS Code editor template, ConfigMap `workshop-env`, Secrets `workshop-credentials` and `workshop-git-credentials` | `admin` |

Also per user: Argo CD AppProject `cn-project-<user>` (namespace `argocd`) and RBAC role, an
Argo CD local account with the `apiKey` capability only, and a Gitea account with the workshop
password.

To create the workspaces without starting them, set `workshopUsers.devspaces.prestartWorkspaces`
to `false` in `charts/workshop/values.yaml`.

## Sizing

Measured on the test cluster (OpenShift 4.22.14, one node with 32 vCPU / 128 GiB) with
`smoke-tests/footprint.sh`; raw numbers in `migration/FINAL-REPORT.md`.

| Scope | Requested (CPU / memory) | Used, idle | Used, Part 1 and Part 2 deployed |
|---|---|---|---|
| Shared platform (Dev Spaces, mesh, Kiali, Argo CD, Gitea, Nexus, Pipelines, lab guide, user workload monitoring) | 4.6 vCPU / 10.5 GiB | 0.3 vCPU / 7.3 GiB | same |
| Operators (`openshift-operators`, GitOps) | 0.6 vCPU / 0.4 GiB | 0.7 GiB | same |
| Per participant: pre-started workspace | 0.28 vCPU / 1.3 GiB (limit 2.5 vCPU / 5.3 GiB) | 0.3 GiB | 0.3 GiB idle, about 2 GiB and 1-2 vCPU while Maven builds run |
| Per participant: `my-project` + `cn-project` apps and databases | 1 GiB (database limits) | 0 | 3.3 GiB |
| Per participant: builds and pipeline runs (transient) | - | - | about 1-2 GiB and 1-2 vCPU per running build |

Planning figure per participant: about 4 GiB steady and up to 6 GiB with builds running, plus
about 10 GiB of persistent volumes (workspace 10 GiB per user, pipeline PVCs 3.5 GiB, both
thin-provisioned). Builds are CPU-heavy (Maven, .NET, npm); concurrent builds of a whole class are
the peak.

| Participants | Memory (steady / peak) | CPU peak | Workers (16 vCPU / 64 GiB each) | Persistent storage |
|---|---|---|---|---|
| 3 | 20 GiB / 26 GiB | 8 vCPU | 1 (or the test cluster's single 32 vCPU / 128 GiB node) | about 60 GiB |
| 10 | 50 GiB / 70 GiB | 20 vCPU | 2 | about 160 GiB |
| 20 | 90 GiB / 130 GiB | 40 vCPU | 3 | about 300 GiB |
| 30 | 130 GiB / 190 GiB | 60 vCPU | 4 | about 440 GiB |

Figures include the shared platform, not the OpenShift control plane or other cluster add-ons.
They assume the default pre-started workspaces (`prestartWorkspaces: true`); without pre-start,
idle participants cost nothing until they open their workspace.

The old guidance of about 8 participants per worker with 16 vCPU / 64 GiB still holds as a
conservative figure; the numbers above show why memory is the limiting resource.

## Lab Guide URL

After sync, get the lab guide route:

```bash
oc get route doc -n lab-guide -o jsonpath='{.spec.host}'
```

The workshop URL format is:

```text
https://<lab-guide-route-host>?OPENSHIFT_USERNAME={username}&OPENSHIFT_PASSWORD={openshift_password}&OPENSHIFT_CONSOLE_URL={openshift_console_hostname}&OPENSHIFT_API_URL={openshift_api_url}
```

A copy of this template is stored in the `lab-guide-url-template` ConfigMap in the `lab-guide`
namespace. The guide derives the apps domain from the console host name. To print the
ready-to-use URL of every participant:

```bash
WORKSHOP_USER_PASSWORD='...' ./print-user-urls.sh          # or --csv
```

## Smoke Tests

```bash
./smoke-tests/platform-check.sh                             # as cluster-admin
WORKSHOP_USER_PASSWORD='...' ./smoke-tests/user-journey.sh user1
WORKSHOP_USER_PASSWORD='...' ./smoke-tests/isolation-check.sh user1 user2
WORKSHOP_USER_PASSWORD='...' ./smoke-tests/user-journey.sh user1 --reset   # back to the initial state
```

`user-journey.sh` logs in as the participant and runs the devfile commands and the guide's steps
inside the participant's workspace, for both parts. It takes 30 to 45 minutes on a fresh cluster
(first Maven downloads fill the Nexus cache).

## Cleanup

Cleanup is handled GitOps-style. Delete the root Application and Argo CD prunes every resource
the charts manage, because every Application has the `resources-finalizer.argocd.argoproj.io`
finalizer and automated pruning enabled:

```bash
oc delete application inner-outer-loop-workshop -n openshift-gitops
```

Operators installed through OLM leave their ClusterServiceVersions and CRDs behind, and some
operators create objects of their own. `cleanup.sh` does the Application deletion above, waits
for it, and then removes those leftovers (and OpenShift GitOps itself unless `--keep-gitops`):

```bash
./cleanup.sh            # asks for confirmation; --yes, --keep-gitops, --keep-crds
```

## Render Locally

```bash
helm template workshop charts/workshop
helm template users charts/workshop-users --set users.count=20
helm lint charts/workshop-users --set 'users.explicitNames={alice,bob}'
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| After the cluster was hibernated or restarted, new Istio `Gateway`s (the per-user ingress gateways of the Service Mesh module) do not route traffic | The gateway pods keep stale configuration from before the hibernation. Restart istiod first, then the gateways: `oc rollout restart deployment/istiod -n istio-system`, then `oc rollout restart deployment/istio-ingressgateway -n cn-project-<user>` for each affected participant (all at once: `for ns in $(oc get ns -o name -l istio-discovery=enabled \| grep cn-project- \| cut -d/ -f2); do oc rollout restart deployment/istio-ingressgateway -n $ns; done`). |
| A child Application stays `Progressing` | Open it in the `openshift-gitops` Argo CD UI. The readiness Jobs in `workshop-setup` (`wait-for-operators`, `wait-for-platform`) and `user-setup` log what they wait for: `oc logs job/<name> -n workshop-setup`. |
| Kiali operator does not install | Its InstallPlan needs approval; the `approve-kiali-ossm` Job in `workshop-setup` does that for the pinned CSV only. Check its log. |
| A workspace is `Failed` | `oc get dw -n devspaces-<user>`. Stop and start it from the Dev Spaces dashboard, or `oc patch dw wksp-end-to-end-dev -n devspaces-<user> --type merge -p '{"spec":{"started":true}}'` after fixing the cause. |
| Kiali graph is empty | User workload monitoring must be running (`oc get pods -n openshift-user-workload-monitoring`), and metrics lag 1 to 2 minutes (30 s scrape interval). |
| `oc login -u` fails for participants | The identity provider must accept the password for the CLI; check the users' passwords in the IdP match `WORKSHOP_USER_PASSWORD`. |
| Participant cannot see their Applications in Argo CD | They must use "LOG IN VIA OPENSHIFT" with their workshop user; Applications must be in project `cn-project-<user>`. |
| `cleanup.sh` waits for namespaces | A finalizer is stuck; `oc get <kind> -n <namespace>` for the objects listed. Operators must still be running while their objects are deleted, which is why the operator namespaces are kept until the end. |

More: `migration/KNOWN-ISSUES.md`.
