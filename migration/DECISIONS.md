# Decisions

Decisions taken during the migration that the migration brief left open. Each has a short
rationale. The fixed decisions of the brief (one workshop, GitOps + Helm, separate participant
Argo CD, reference tooling, URL parameters, `users.*` interface, no portal, modernize only where
needed, screenshot TODO list, declarative workspaces, no external shared services) are not
repeated here.

## D1. Source branches

All branches named in the brief (`workshop-operator` 2.13, `end-to-end-developer-workshop` 6.11,
`inner-loop-guide` 6.9, `outer-loop-guide` 6.11) are the newest version branches of their
repositories (`git ls-remote --heads` on 2026-09-23); none is newer. Non-version branches
(`rhds`, `completed`, `demo-mode`, `gh-pages`, dependabot branches) were ignored. The tooling image
source `workshop-tools` (MIGRATION.md, section 1; the version the old devfile used) was
cloned as an additional read-only source because the image had to be rebuilt (D14).

## D2. App-of-apps split

The root Application `inner-outer-loop-workshop` renders four child Applications:
`workshop-operators` (wave 0), `workshop-platform` (wave 1), `workshop-users` (wave 2) and
`workshop-lab-guide` (wave 0). The split follows the dependency chain: operand CRs need their
operators' CRDs and webhooks, per-user objects need Dev Spaces, Argo CD and Gitea to be serving,
while the lab guide depends on nothing. Keeping one chart per layer keeps each Application's
health meaningful in the Argo CD UI and lets an instructor resync one layer. Finer splits (one
Application per product) were rejected: they add ordering edges without adding control.

## D3. Waiting for readiness

Argo CD's built-in Subscription health only reflects OLM resolution (a Subscription is Healthy
once its InstallPlan is complete, not when the CSV has finished installing), and most operands
(Istio, Kiali, Gitea, participant ArgoCD) have no built-in health check. Instead of custom Lua
checks for every kind, each layer ends with a Sync-hook Job that waits for the real condition:
`wait-for-operators` (every Subscription's installed CSV and all CSVs in the operator namespaces
are `Succeeded`) and `wait-for-platform` (CheCluster `Active`, Istio/IstioCNI `Ready`, Kiali,
Argo CD `Available`, Gitea admin set up, Nexus available). `bootstrap.sh` adds one custom health
check for `argoproj.io/Application` that reports a child as Healthy only when it is Synced,
Healthy and its last operation (including hook Jobs) Succeeded; the root Application's sync waves
therefore wait for each layer. Verified on the test cluster: without the Application check, all
children would start at once.

## D4. Operator channels and approval

Channels verified with `oc get packagemanifest` on OpenShift 4.22.14:

| Operator | Package | Channel | Approval | Namespace |
|---|---|---|---|---|
| OpenShift GitOps | `openshift-gitops-operator` | `gitops-1.21` | Automatic (bootstrap.sh) | `openshift-gitops-operator` |
| Dev Spaces | `devspaces` | `stable` (only channel, 3.30) | Automatic | `openshift-operators` |
| Pipelines | `openshift-pipelines-operator-rh` | `pipelines-1.24` | Automatic | `openshift-operators` |
| Service Mesh 3 | `servicemeshoperator3` | `stable-3.4` | Automatic | `openshift-operators` |
| Kiali | `kiali-ossm` | `stable` (the other channel, `candidate`, is a preview) | **Manual**, `startingCSV: kiali-operator.v2.27.4` | `kiali-operator` |
| Gitea | `gitea-operator` | `stable` | Automatic, catalog image pinned to `v2.3.2` | `gitea-operator` |

The DevWorkspace operator is not subscribed by the chart: OLM installs it as a dependency of Dev
Spaces from its only channel, `fast` (v0.43.0 on the test cluster), in `openshift-operators`.
Subscribing it explicitly as well would race with OLM's dependency resolution.

Minor-version channels (`gitops-1.21`, `pipelines-1.24`, `stable-3.4`) limit Automatic upgrades to
patch releases. Kiali's supported channel is `stable` (plus a `candidate` preview channel), so a channel alone cannot hold a version, and it is the operator with a known upgrade hazard
(an automatic upgrade once broke the mesh), so it is pinned: Manual approval, a pinned
`startingCSV`, and a Job that approves exactly that CSV's InstallPlan. It runs in its own
namespace because OLM install plans are per namespace: a Manual subscription in
`openshift-operators` would hold back upgrades of every other operator there. The approval Job
runs in the same sync wave as the Subscriptions because Argo CD reports a Subscription with a
pending InstallPlan as Progressing, which would block any later wave (found on the test cluster).

## D5. Istio version

Istio `v1.30-latest` (the newest minor supported by OSSM 3.4.2 according to the `Istio` CRD) with
`InPlace` updates. `-latest` follows patch releases of 1.30 only. Kiali 2.27.4 is the Kiali
version shipped for OSSM 3.4.

## D6. Gitea: rhpds Gitea operator

The old operator deployed Gitea with `quay.io/gpte-devops-automation/gitea-operator:v1.2.3`
(2021, unmaintained). Its maintained successor is the Red Hat Demo Platform
`rhpds/gitea-operator` (v2.3.2, April 2026), installable through OLM from
`quay.io/rhpds/gitea-catalog`. It is used for the Gitea instance and its admin account, with
the CR name `gitea-server` so the service stays `gitea-server.gitea.svc:3000`. Participant
accounts are **not** created by the operator, because it can only generate `<prefix><n>` names
and the chart must support `users.explicitNames`. The users chart's `user-setup` Job creates them
through the Gitea admin API with `WORKSHOP_USER_PASSWORD`. Self-registration is disabled.

## D7. Nexus: plain manifests

No suitable operator exists: `nexus-operator-m88i` is archived, the EPAM `nexus-operator` only
configures an existing Nexus, and Sonatype's certified operator deploys the paid Pro edition.
Nexus is therefore deployed from plain manifests (`docker.io/sonatype/nexus3`, pinned tag) with
a Sync-hook Job that configures it through the REST API: random admin password (kept in the
cluster), Community Edition EULA acceptance, anonymous read, the `maven-central`, `redhat-ga` and
`jboss` proxies and the `maven-all-public` group (same repositories as the old setup). Namespace
and service are `nexus`/`nexus`, so the mirror URL is
`http://nexus.nexus.svc:8081/repository/maven-all-public/` (no `opentlc` name).

## D8. Participant Argo CD: OpenShift login plus API tokens

Participants log in to the `argocd` instance (route `argocd-server-argocd.<apps domain>`) with
OpenShift (Dex `openShiftOAuth`). RBAC in the ArgoCD CR gives `role:<user>` access to
`applications`, `applicationsets`, `logs` and `repositories` of project `cn-project-<user>` only;
the default policy is empty. The old workshop also used Argo CD local accounts with the workshop
password for non-interactive use (the CD pipeline Task and a devfile script ran `argocd login`
with username and password). Those cannot use SSO, so each participant also gets a local account
with the same name and **only** the `apiKey` capability (no password login). The `user-setup` Job
issues a token per account and stores it as Secret `argocd-env-secret` in `cn-project-<user>`
(read by the pipeline Task through `ARGOCD_AUTH_TOKEN`, which the Task already supported) and in
the workspace credentials. The guide step that asked participants to create a Secret with their
password now inspects the pre-created token Secret instead.

## D9. Pre-created projects

The old setup pre-created only `cn-project<N>`; participants created `my-project<N>` with
`oc new-project`. The chart now pre-creates `my-project-<user>` too (like the reference, which
pre-creates every per-user namespace): it makes provisioning, isolation checks and cleanup
declarative and works on clusters where self-provisioning is disabled. The devfile command
"OpenShift - Create Development Project" becomes idempotent (`oc project` or create), and the guide
step says the project was prepared. Participants get `admin` in `my-project-<user>` and their Dev
Spaces namespace, and `edit` in `cn-project-<user>` (as in the old setup, which Argo CD manages).
No quotas or limit ranges are applied, same as the old setup; sizing is documented instead.

## D10. Dev Spaces workspaces

The old operator created per user: namespace `user<N>devspaces`, ConfigMaps for `settings.xml`
and `.gitconfig`, a che-code DevWorkspaceTemplate and a started DevWorkspace
`wksp-end-to-end-dev` whose content it parsed from the devfile at runtime. The users chart does
the same declaratively in `devspaces-<user>`:

- DevWorkspace `wksp-end-to-end-dev` with `spec.template.parent.uri` pointing at the raw devfile
  of the code repository, so the devfile is not duplicated in the chart; `spec.started` follows
  `devspaces.prestartWorkspaces` (default `true`) and is in `ignoreDifferences` so participants
  can stop and restart their workspace.
- DevWorkspaceTemplate `che-code-wksp-end-to-end-dev`, copied from the Dev Spaces 3.30
  `editors-definitions` ConfigMap (image digests in values).
- ConfigMap `workshop-env` (mounted as environment variables): `WORKSHOP_USER`,
  `WORKSHOP_DEV_PROJECT`, `WORKSHOP_STAGING_PROJECT`, `WORKSHOP_GITEA_URL`, `MAVEN_MIRROR_URL`,
  `ARGOCD_SERVER`, `ARGOCD_OPTS` and the Git author/committer identity (replaces `.gitconfig`).
- Secrets from the `user-setup` Job: `workshop-credentials` (env: `WORKSHOP_PASSWORD`,
  `ARGOCD_AUTH_TOKEN`) and `workshop-git-credentials` (DevWorkspace Git credential for Gitea).

The Maven mirror `settings.xml` moved into the tooling image as global settings
(`${env.MAVEN_MIRROR_URL}`), so it no longer needs a per-user ConfigMap. The Dev Spaces
namespace pattern is `devspaces-<username>` (the brief's `<purpose>-<username>` style) instead of
the Dev Spaces default `<username>-devspaces`.

## D11. User workload monitoring

Enabled through the `cluster-monitoring-config` ConfigMap (platform chart), as the old operator
did, because Kiali's graph and traffic distribution steps need Istio metrics that only user
workload monitoring scrapes. The ConfigMap did not exist on the test cluster. If a cluster
already has one with other settings, it must be merged before bootstrapping (README).

## D12. Java 21 builder for `s2i-java`

The Pipelines 1.24 `s2i-java` Task builds from `openshift/java:<VERSION>`, and OpenShift 4.22's
Samples operator no longer provides a Java 21 tag there (only up to `openjdk-17-ubi8`). The
platform chart's `cluster-integration` Job adds `openshift/java:openjdk-21-ubi9` from
`registry.access.redhat.com/ubi9/openjdk-21` (the Samples operator leaves additional tags
alone). It is a Job and not a manifest because ImageStreamTags cannot carry Argo CD's tracking
labels (verified: the patch is rejected). The same Job enables the `pipelines-console-plugin`
(the Pipeline builder the guide uses), as the old operator did, by appending to the shared
console plugin list.

## D13. Lab guide placeholders

The Showroom theme replaces `%KEY%` in text and links with the URL parameter `KEY`,
case-insensitively. Pages only use AsciiDoc attributes (`{OPENSHIFT_USERNAME}` etc.; code blocks
use `subs="attributes+"`), and `antora.yml` maps each attribute to a lowercase token such as
`%openshift_username%`. That keeps the reference mechanism unchanged while letting
`grep -rE '%[A-Z_]+%'` stay a meaningful check for leftover operator-era placeholders. The apps
domain is derived in the browser from `OPENSHIFT_CONSOLE_URL` (strip `console-openshift-console.`)
by a small head script that adds `OPENSHIFT_APPS_DOMAIN` to the query string before the theme runs,
so the URL template keeps the reference's four parameters.

## D14. Tooling image rebuilt

The old `workshop-tools:6.9` image still starts on Dev Spaces 3.30, but it ships
`oc` 4.15, `argocd` 2.7 (the server is Argo CD 3.4), yq 2.4 and Maven 3.8, lives in the old
organisation, and has no build pipeline. It is rebuilt from its Dockerfile (source:
see MIGRATION.md, section 1) on UBI 9 with current tools and published as
`quay.io/mostmark/workshop-tools:latest`; the Containerfile lives in the code repository.

## D15. Supplemental UI wiring of the lab guide

The reference's `site.yml` lists `./content/supplemental-ui` and `./content/lib` as
`supplemental_files` list entries without `contents`. Antora only adds a list entry's
`contents`, so these entries add nothing (the reference's `head-meta.hbs`, `header-content.hbs`
and CSS overrides are not active in its own build either; verified by building both). To keep the
look of the reference as deployed, those entries were copied verbatim and only the workshop's
`partials/head-scripts.hbs` (apps domain derivation) is wired with an explicit `contents` entry.

## D16. JKube and DeploymentConfig

JKube 1.11 and even 1.20 still default to a DeploymentConfig on OpenShift. Instead of the old
enricher configuration (`jkube-openshift-deploymentconfig` with `switchToDeployment`), the catalog
pom sets the documented global property `jkube.build.switchToDeployment=true`; the generated
resources are a Service, a Deployment and a Route (verified with `mvn oc:resource`). The guide's
pom snippet no longer mentions DeploymentConfig. Spring Boot 2.1 stays (it builds and runs on
Java 21; an upgrade would change the exercise code).

## D17. Smoke tests run the participant's steps in the participant's workspace

`user-journey.sh` logs in as the participant with the workshop password (a separate kubeconfig),
starts the pre-created workspace if needed, and runs the devfile commands (read from the
workspace's own `devfile.yaml`) and the guide's solution scripts with `oc exec` in the
`workshop-tools` container, as a participant would in a workspace terminal. Console and UI steps
the guide does by hand (Pipeline Builder, Argo CD UI) are replaced by their CLI/API equivalents
from the solution scripts. The Argo CD OpenShift login is verified separately by
`isolation-check.sh`, which scripts the browser flow (Argo CD → Dex → OpenShift OAuth → identity
provider → consent) and checks the resulting session's RBAC in both Argo CD instances.

## D18. Cleanup order

`cleanup.sh` deletes the root Application first, so Argo CD removes everything from Git while all
operators still run and can process their finalizers (operator namespaces carry `Delete=false`
for that reason). Only then does it remove what OLM and the operators created: TektonConfig
(waiting for its installer sets before the Pipelines operator goes), the operators' Subscriptions
and CSVs, run-time objects (ConsolePlugins, the pipelines SCC, webhooks, ClusterRoles), CRDs, and
finally OpenShift GitOps (default instance disabled first, because the operator re-creates it).
The script verifies the end state and fails if anything is left. Found and fixed on the test
cluster over three cleanup runs; the final version cleaned a complete installation with
participant content in one pass (FINAL-REPORT section 4).

## D19. Showing one part of the lab guide (two-day events)

The workshop is often run as two half days (Part 1 on day 1, Part 2 on day 2), and participants
should only see the part of the day. The choice is made on the server, not in the browser: an
Antora extension (`content/lib/workshop-part-extension.js`) builds the site for `WORKSHOP_PART`
`all`, `inner` or `outer` (it removes the other part's pages and navigation section and sets the
`workshop-part` attribute that the Home page and the two Part 2 pages linking to Part 1 use), the
image contains all three builds, and httpd serves the one named by the container's
`WORKSHOP_PART` variable. The root chart's `guidePart` value sets that variable on the lab guide
Deployment. Switching between the days is a parameter change (`set-guide-part.sh`) that only
restarts the lab guide pod; participants keep their URLs and their work. Hiding the other part
client-side (URL parameter, CSS) was rejected because it is easy to get around. Provisioning is
not split by part: Part 2 needs the whole platform, and installing everything once keeps day 2
free of setup time. The GitHub Pages preview shows the whole workshop.
