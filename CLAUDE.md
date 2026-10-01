# Inner & Outer Loop Workshop: installation (OpenShift GitOps + Helm)

Installs the Inner & Outer Loop workshop on an OpenShift cluster: operators, shared platform,
per-user resources and the lab guide, as an app-of-apps in the admin-only `openshift-gitops`
Argo CD instance. `README.md` is the user documentation; `docs/` holds the known issues, the design decisions and
the origin of the content.

Related repositories (all use only the `main` branch):

- `github.com/mostmark/inner-outer-loop-workshop`: the lab guide (image
  `quay.io/mostmark/inner-outer-loop-lab:latest`).
- `github.com/mostmark/inner-outer-loop-workshop-code`: what participants get in their workspace
  (code, devfile, task scripts, pipelines). It has no `CLAUDE.md` of its own; its rules are in
  "Working on the code repository" below.

## Layout

| Path | What |
|---|---|
| `argocd/application.yaml` | root Application `inner-outer-loop-workshop` (source `main`) |
| `charts/workshop/` | root chart: renders the child Applications (sync waves 0-2) |
| `charts/workshop-operators/` | Subscriptions, OperatorGroups, CatalogSource, readiness Jobs |
| `charts/workshop-platform/` | shared instances: Dev Spaces, Service Mesh + Kiali, participant Argo CD, Gitea, Nexus, Pipelines, database templates, monitoring |
| `charts/workshop-users/` | per-user namespaces, RBAC, workspaces, and the user-setup Job (Gitea accounts, tokens, credentials) |
| `charts/lab-guide/` | lab guide Deployment, Route, URL template |
| `bootstrap.sh` | the only imperative step: GitOps operator, secrets, root Application |
| `cleanup.sh` | removes the workshop and every cluster-wide change, then verifies the end state |
| `print-user-urls.sh`, `set-guide-part.sh`, `lib/credentials.sh` | participant URLs, lab guide part, user passwords |
| `smoke-tests/` | `platform-check.sh`, `isolation-check.sh`, `user-journey.sh`, `footprint.sh` |
| `tools/` | source of the participants' tooling image `quay.io/mostmark/workshop-tools:latest` (`Containerfile`, `build-push.sh`, `etc/` with `.bashrc`, Maven settings, entrypoint); the Maven warm-up Job uses it too |
| `docs/` | `known-issues.md` (workarounds, when to remove them), `decisions.md` (why things are built this way), `origin.md` (sources and migration record, attribution) |

## Rules

- **No secrets in Git.** User passwords, the Gitea admin password and tokens are created in the
  cluster by `bootstrap.sh` or by Jobs. Never commit a password, a credentials file (`*.csv` is
  ignored), a kubeconfig or a token.
- **Charts are cluster-agnostic**: no apps domain, host names or IP addresses in values. Values that
  depend on the cluster are read at run time (for example the Dev Spaces URLs from the CheCluster
  status in the user-setup Job).
- Least privilege for participants: no cluster-admin, no broad SCC grants; `anyuid` only with a
  written reason. Participant roles are `admin` in `my-project-<user>` and `devspaces-<user>`,
  `edit` in `cn-project-<user>`.
- Objects owned by an operator or shared by the cluster are changed with server-side apply of the
  needed fields only and marked `argocd.argoproj.io/sync-options: Delete=false` (see the Samples
  operator `Config` in `charts/workshop-platform/templates/sample-templates.yaml`).
- Every cluster-wide change must be undone by `cleanup.sh` and covered by its end-state check.
- Verify API versions, fields and operator channels on a cluster (`oc explain`,
  `oc api-resources`, `oc get packagemanifest`) instead of assuming them.
- Record decisions in `docs/decisions.md` and workarounds in `docs/known-issues.md`
  (with when to remove them), and keep `README.md` in step with behaviour changes.

## What you need

- An OpenShift 4.22 cluster (x86_64) with cluster-admin, a default storage class, the internal image
  registry, and the participant users in its identity provider (README, "Prerequisites").
- `oc` logged in as cluster-admin, `helm` for the chart checks, push rights to the repository that
  Argo CD follows.
- Sizing and the user passwords are in `README.md`.

## How changes reach users

| Change | Reaches |
|---|---|
| push to `main` | every cluster whose root Application follows this repository: Argo CD syncs it (refresh the Application to speed it up) |
| `bootstrap.sh` | the GitOps operator, the secrets (user passwords) and the root Application's parameters |
| a changed Job (Sync hook) | runs again on the next sync of its Application |
| `tools/build-push.sh` | workspaces started afterwards (the tooling image is pulled anew); restart running ones |
| running workspaces | read their environment at start: they get changed values after a restart (the DevWorkspace operator restarts them itself when a mounted ConfigMap or Secret is added) |

## Checks before committing

- `helm lint` and `helm template` for every chart (and the root chart with its value variants).
- `bash -n` for changed scripts.
- On a test cluster: `./smoke-tests/platform-check.sh` (all checks pass), for bigger changes also
  `isolation-check.sh` and `user-journey.sh <user>`. Argo CD on the cluster follows `main`, so a
  push deploys the change there.

## Switches in the charts

| Value | Default | Purpose |
|---|---|---|
| `guidePart` (root) | `all` | lab guide shows `all`, `inner` (Part 1) or `outer` (Part 2); `set-guide-part.sh` |
| `workshopUsers.kialiEditWorkaround` | `true` | Role that lets participants edit Istio config in Kiali 2.27 (docs/known-issues.md K19); remove with Kiali 2.28+ |
| `databaseTemplates.hideSampleTemplates` (platform) | `true` | hides OpenShift's sample MariaDB/PostgreSQL templates (K20) |
| `devspaces.prestartWorkspaces` (users) | `true` | starts each participant's workspace |
| `devspaces.fsGroupChangePolicy` (platform) | `OnRootMismatch` | workspace starts skip setting the group of every file on the volume (docs/known-issues.md K21) |
| `nexus.warmup.enabled` (platform) | `true` | Job `maven-warmup` fills the Nexus cache with the Java builds of the code repo (docs/decisions.md D23) |

## Names and contracts shared with the other repositories

- Users come from `users.count` / `users.prefix` / `users.explicitNames`; per-user names use the
  full user name: `my-project-<user>`, `cn-project-<user>`, `devspaces-<user>`, workspace
  `wksp-end-to-end-dev`, Argo CD AppProject `cn-project-<user>` in namespace `argocd`.
- Services: Gitea (`gitea`, `http://gitea-server.gitea.svc:3000`), Nexus Maven mirror (`nexus`,
  `http://nexus.nexus.svc:8081/repository/maven-all-public/`), participant Argo CD (`argocd`, OpenShift
  login), Kiali (`istio-system`), lab guide (`lab-guide`, route `doc`). `openshift-gitops` is
  admin-only.
- Workspace environment (ConfigMaps `workshop-env`, `workshop-devspaces-env` and Secret
  `workshop-credentials`, mounted as environment variables): `WORKSHOP_USER`, `WORKSHOP_DEV_PROJECT`,
  `WORKSHOP_STAGING_PROJECT`, `WORKSHOP_GITEA_URL`, `MAVEN_MIRROR_URL`, `ARGOCD_SERVER`, `ARGOCD_OPTS`,
  `ARGOCD_AUTH_TOKEN`, `WORKSHOP_PASSWORD`, `GIT_*`, `CHE_DASHBOARD_URL` and the plugin registry URLs.
- Pipelines authenticate to Argo CD with Secret `argocd-env-secret` (key `ARGOCD_AUTH_TOKEN`) in
  `cn-project-<user>`.
- Database templates `coolstore-mariadb` / `coolstore-postgresql` in `openshift` (Deployments,
  MariaDB 10.5, PostgreSQL 15); the lab guide and the code repo's solutions depend on them.

## Updating versions

Check new versions on a cluster (`oc get packagemanifest <name> -o yaml`) and keep the dependent
values in step:

| What | Where | Depends on it |
|---|---|---|
| OpenShift GitOps channel | `bootstrap.sh` (`GITOPS_CHANNEL`) | the `argocd` CLI in the tooling image (`ARGOCD_VERSION` in `tools/Containerfile`) |
| Dev Spaces, Pipelines, Service Mesh channels | `charts/workshop-operators/values.yaml` | Pipelines: `TKN_VERSION` in `tools/Containerfile` |
| Kiali: channel + `startingCSV` (manual approval, a Job approves exactly that CSV) | `charts/workshop-operators/values.yaml` | `workshopUsers.kialiEditWorkaround` can go with Kiali 2.28+ (docs/known-issues.md K19) |
| Gitea operator: pinned catalog image tag | `charts/workshop-operators/values.yaml` (`catalogSources`) | - |
| Dev Spaces editor image digests | `charts/workshop-users/values.yaml` (`devspaces.editor`) | copy them from the `che-code.yaml` entry of ConfigMap `editors-definitions` in `openshift-devspaces` after every Dev Spaces minor upgrade |
| Istio version, Nexus image, Java builder tag, database versions | `charts/workshop-platform/values.yaml` | Java builder tag: the code repo's `s2i-java` `VERSION`; MariaDB version: the inventory service's `db-version` in the lab guide and the code repo |
| Product versions shown in the lab guide | the lab guide's `content/antora.yml` | - |
| Tools in the tooling image | `tools/Containerfile` (`ARG` lines) | `OC_CHANNEL` with OpenShift, `TKN_VERSION` with Pipelines, `ARGOCD_VERSION` with OpenShift GitOps; also `MAVEN_VERSION`, `YQ_VERSION` |

Record version changes and anything they break in `docs/known-issues.md`.

## Customising in a fork

These values point to the original repositories and images; change all of them together with the
list in the lab guide repository's `CLAUDE.md` and the code repository's list below:

- `argocd/application.yaml`: `spec.source.repoURL` and the `source.repoURL` parameter.
- `bootstrap.sh`: default `REPO_URL` (or pass `--repo`).
- `charts/workshop/values.yaml`: `source.repoURL`.
- `charts/lab-guide/values.yaml`: `labGuide.image`.
- `charts/workshop-users/values.yaml`: `devspaces.devfileURL`, `devspaces.repositoryURL`.
- `charts/workshop-platform/values.yaml`: `nexus.warmup.image`, `nexus.warmup.repositoryURL`.
- `tools/build-push.sh` (run it with your `QUAY_USER`), the header and source label in
  `tools/Containerfile`, and `tools/README.md`.
- `README.md` and this file: repository and image names.

## Working on the code repository

`github.com/mostmark/inner-outer-loop-workshop-code` is cloned into every participant's workspace
(`/projects/workshop`), so **everything in it is visible to participants**. Keep it to what they
need, like the original workshop: `labs/`, `.tasks/`, `devfile.yaml`, `.gitignore` and a short
participant `README.md` (overview only, no installation or maintainer details). Maintainer material
(the tooling image, installation notes, these rules) belongs in this repository.

| Path in the code repository | What |
|---|---|
| `devfile.yaml` | workspace definition (tooling container, endpoints, devfile commands) |
| `.tasks/` | scripts behind the devfile commands; all source `.tasks/workshop-env.sh` (user and project names, `workshop_login`, `workshop_clean_project`, Gitea helpers) |
| `.tasks/solutions/` | the finished state of the exercises that the "... - Deploy Coolstore" commands apply |
| `labs/` | the services (`inventory-quarkus`, `catalog-spring-boot`, `gateway-dotnet`, `web-nodejs`, `catalog-go`) and `pipelines`; `labs/README.md` describes the application for participants |

Rules:

- **Devfile command labels must not change**: the lab guide tells participants to run them by name
  (for example "OpenShift - Login", "Inner Loop - Deploy Coolstore"). Adding commands is fine.
- Scripts get their values from the workspace environment (section "Names and contracts") and fall
  back to names derived from the namespace (`${DEVWORKSPACE_NAMESPACE#devspaces-}`).
- Never put passwords or tokens in files or Git URLs; the workspace gets them from the user-setup Job.
- `workshop_clean_project` must remove everything a participant can create in a project, including
  DeploymentConfigs and TemplateInstances from OpenShift's sample templates.
- Solutions must match the lab guide (for example `%prod.quarkus.datasource.db-version=10.5`, which
  matches the Coolstore MariaDB template).
- Tekton: `tekton.dev/v1`; tasks via `resolver: cluster` from `openshift-pipelines` (`git-clone`,
  `s2i-java` with `VERSION: openjdk-21-ubi9`, which must match `pipelines.javaBuilderTag` here,
  `s2i-nodejs`, `s2i-dotnet`, `openshift-client`; param `CONTEXT`).
- Service Mesh 3: `networking.istio.io/v1`; per-user gateway label `istio: ingressgateway-<user>`.
- Default Git branch everywhere: `main` (`git init -b main`).
- The platform chart's `maven-warmup` Job runs `.tasks/solutions/inventory-quarkus/solve.sh` and
  `.tasks/solutions/catalog-spring-boot/solve.sh`, then builds `labs/inventory-quarkus` and
  `labs/catalog-spring-boot` (`templates/maven-warmup.yaml`). Moving or renaming these, or adding a
  Java service, needs the matching change there. After changing Maven dependencies on a running
  workshop, sync the platform Application to fill the cache again.
- Framework versions are in each service's build file (for example `quarkus.platform.version` in
  `labs/inventory-quarkus/pom.xml`); the lab guide shows some of these files, so check its text too.

How changes reach participants: a push to `main` reaches workspaces created afterwards (they clone
`main`); existing workspaces need `git pull` in `/projects/workshop`. Test with a participant's
workspace and the devfile commands, or run `smoke-tests/user-journey.sh <user>` from here.

In a fork, change in the code repository: `devfile.yaml` (the project's `origin` URL and the
tooling image), the default `CODE_REPO_URL` in `.tasks/workshop-env.sh`, and the repository, bugs
and homepage URLs in `labs/web-nodejs/package.json`.

## Git

- Only `main`; no version branches or tags; `targetRevision: main`, images tagged `latest`.
- Commit messages without AI or Claude attribution.
