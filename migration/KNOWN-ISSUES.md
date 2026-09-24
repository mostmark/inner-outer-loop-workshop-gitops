# Known issues

Open issues and limitations of the migrated workshop, with workarounds. Items fixed during the
migration are in [MIGRATION.md](MIGRATION.md) and [FINAL-REPORT.md](FINAL-REPORT.md).

## Workshop content

| # | Issue | Impact | Workaround / next step |
|---|---|---|---|
| K1 | Screenshots still show the old console, Dev Spaces, Argo CD, Kiali and Gitea UIs and old names (`user1devspaces`, `my-project1`, password Secret). | Cosmetic; a few images contradict the new text (marked P1). | Recapture following `SCREENSHOTS-TODO.md` in the content repository. |
| K2 | The catalog service still uses Spring Boot 2.1 (Java 8 source level) and JKube 1.11. It builds and runs on Java 21 and JKube now generates a Deployment, but both are long out of support. | None for the exercises. | Upgrading to Spring Boot 3 changes the Catalog exercise code (`javax` to `jakarta`); out of scope ("modernize only where needed"). |
| K3 | .NET 9 support ends in November 2026; `dotnet:10.0` is available on OpenShift 4.22. | The Gateway exercise keeps `dotnet:9.0`. | Switch the devfile command, `.tasks` and the guide to `dotnet:10.0` when .NET 9 leaves support. |
| K4 | The "Fix up the Browser URL" subsection (browsers upgrading plain `http://` app routes to `https://`) depends on the browser. | Participants may not see the problem. | Kept, because Chrome's HTTPS-first mode still does this. |
| K5 | The guide's sample outputs (e.g. the GitOps commit file list) are representative; exact output depends on which resources exist. | None. | - |

## Platform

| # | Issue | Impact | Workaround / next step |
|---|---|---|---|
| K6 | Nexus Community Edition has usage limits (40,000 components, 100,000 requests per day) and asks for EULA acceptance. The config Job accepts the EULA. CI pipelines with `MAVEN_CLEAR_REPO` re-download dependencies from Nexus on every build. | With 30 participants the daily request count can exceed the limit; Nexus then warns and, after a grace period, restricts new components. A one-day workshop stays within the grace period. | Monitor the Nexus usage page for multi-day events; drop `MAVEN_CLEAR_REPO=true` from the pipelines to reduce requests. |
| K7 | The Dev Spaces editor definition (che-code image digests) is copied into `charts/workshop-users/values.yaml` from Dev Spaces 3.30. Dev Spaces is on the `stable` channel with Automatic approval. | After a Dev Spaces minor upgrade, pre-created workspaces keep the 3.30 editor images (still pullable) until the values are updated. | Update `devspaces.editor.*` from the `editors-definitions` ConfigMap after an upgrade. |
| K8 | Kiali is pinned (`startingCSV` + Manual approval). Newer Kiali versions are never installed automatically. | Intended (upgrade hazard of the old setup). | Change `subscriptions.kiali.startingCSV` in `charts/workshop-operators/values.yaml` together with the OSSM channel. |
| K9 | Istio gateway pods may need a restart after cluster hibernation before new Gateways route traffic. | Service Mesh module after a hibernated cluster resumes. | README, Troubleshooting. |
| K10 | Argo CD owns the `cluster-monitoring-config` ConfigMap. | On clusters that already have one, bootstrapping replaces its content. | Merge existing settings into `charts/workshop-platform/templates/monitoring.yaml`, or set `monitoring.enableUserWorkload=false` and enable user workload monitoring yourself. |
| K11 | `bootstrap.sh` gives the `openshift-gitops` application controller `cluster-admin`. | Anyone who can create Applications in `openshift-gitops` in project `default` can do anything on the cluster. | `openshift-gitops` is admin-only; participants have no access to it (verified by `isolation-check.sh`). |
| K12 | The workshop users must exist in the identity provider with the password passed as `WORKSHOP_USER_PASSWORD`, and the IdP must support the password grant for `oc login -u -p` (used by the devfile's "OpenShift - Login" and the smoke tests). | On the test cluster the Keycloak realm had different per-user passwords; they were reset to `WORKSHOP_USER_PASSWORD` in Keycloak (with the owner's approval) before testing. | Make sure the users' passwords match before an event. |
| K13 | If Argo CD re-creates a DevWorkspace while a failed one with `spec.started: false` still exists, the new one keeps `started: false` (the field is in `ignoreDifferences` on purpose). | Seen only when deleting failed workspaces by hand. | Start the workspace from the dashboard. |
| K14 | Participants' Argo CD access uses both SSO (UI) and an API token of a local account with the same name (pipelines, devfile scripts). Tokens are issued by the `user-setup` Job and do not expire. | Tokens stay valid for the lifetime of the participant Argo CD instance. | Cleanup removes the instance; re-bootstrapping issues new tokens. |
| K17 | The `WORKSHOP_USER_PASSWORD` used on the test cluster is the old workshop's well-known default password, which the imported upstream code hard-coded. It therefore appears in Git history: in the code repository (the verbatim import commit and the diff of the commit that removed it) and in two early commits of this repository's migration notes. No current file in any repository contains it as a credential. | Anyone who reads the public history learns that default, not a secret of this setup. | Use a different, event-specific password for real events (`WORKSHOP_USER_PASSWORD` is only stored in the cluster). |

## Repositories

| # | Issue | Impact | Workaround / next step |
|---|---|---|---|
| K15 | GitHub Pages had to be enabled on the new content repository (build type "GitHub Actions") before the copied workflow could publish the preview site. | Done for `mostmark/inner-outer-loop-workshop`; forks must do the same. | Settings > Pages > Source: GitHub Actions. |
| K16 | The reference's `site.yml` lists `./content/supplemental-ui` and `./content/lib` as `supplemental_files` entries without `contents`, so Antora adds nothing for them (the reference's header and CSS overrides are not active there either). They were kept verbatim; only `partials/head-scripts.hbs` is wired explicitly. | The site looks like the reference as deployed. | If the RHDP header should be active, add `contents:` entries for the files in `content/supplemental-ui`. |
