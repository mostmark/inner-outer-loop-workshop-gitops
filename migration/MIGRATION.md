# Migration record

The Red Hat "End-to-End Developer Workshop" (Inner Loop + Outer Loop) moved from the
`workshop-operator` to OpenShift GitOps and Helm, with one Antora lab guide. This file records
where everything came from, how the old components map to the new ones, how every guide page was
migrated, and what changed and why. Decisions are in [DECISIONS.md](DECISIONS.md), the full
component inventory in [COMPONENT-INVENTORY.md](COMPONENT-INVENTORY.md).

## 1. Sources

All content was imported as fresh history (no branches or tags carried over). Attribution: the
original workshop was written by the Red Hat EMEA Solution Architects team and published by
Red Hat Scholars; the reference implementation is the Network Policies workshop.

| Purpose | Repository | Branch | Commit |
|---|---|---|---|
| Spec of what must be provisioned | `github.com/RedHat-EMEA-SSA-Team/workshop-operator` | `2.13` | `7817482fc642eefc48f995167192517a8be7e307` |
| Example code + devfile | `github.com/RedHat-EMEA-SSA-Team/end-to-end-developer-workshop` | `6.11` | `2f474c4be18cee50e3f5a7e2558d63634068440e` |
| Tooling image source | `github.com/RedHat-EMEA-SSA-Team/workshop-tools` | `6.9` | `7bb199af43e204b0cd1ffad41946357e4e04bd6a` |
| Inner Loop guide | `github.com/redhat-scholars/inner-loop-guide` | `6.9` | `1b78dab606f293d796a9b3584505063df602c33b` |
| Outer Loop guide | `github.com/redhat-scholars/outer-loop-guide` | `6.11` | `11d20c0a5017c615ec1dc0bfe8ee2dcb97eee153` |
| Reference: lab guide pattern | `github.com/mostmark/network-policies-workshop` | `main` | `ff48cc0ecb957eb3c684ea1454cef4e66aa25ce4` |
| Reference: GitOps pattern | `github.com/mostmark/network-policies-workshop-gitops` | `main` | `4c445cb197eb1c0a2b5f174f123974d16a67fef6` |

`git ls-remote --heads` (2026-09-23) showed no newer version branch for any source.

Targets (all only `main`):

| Repository | Content |
|---|---|
| `github.com/mostmark/inner-outer-loop-workshop` | Antora lab guide, image `quay.io/mostmark/inner-outer-loop-lab:latest`, `SCREENSHOTS-TODO.md` |
| `github.com/mostmark/inner-outer-loop-workshop-gitops` | Helm charts, root Application, `bootstrap.sh`, `cleanup.sh`, `print-user-urls.sh`, `smoke-tests/`, `migration/` |
| `github.com/mostmark/inner-outer-loop-workshop-code` | Example code, devfile, `.tasks`, pipelines, tooling image `quay.io/mostmark/workshop-tools:latest` |

## 2. Old to new component mapping

| Old (workshop-operator 2.13) | New |
|---|---|
| `Workshop` CR, `spec.user.number` | Root Application `inner-outer-loop-workshop` with `users.count`, `users.prefix`, `users.explicitNames` |
| Operator Deployment in `workshop-infra` | Argo CD (`openshift-gitops`) + four child Applications (operators, platform, users, lab guide) |
| Subscriptions created in code, InstallPlans approved in code | `charts/workshop-operators`: pinned channels, Automatic approval except Kiali (pinned CSV + approval Job), readiness Job |
| CheCluster v1 fields, `<username>devspaces` | `charts/workshop-platform`: CheCluster v2, `devspaces-<username>` |
| DevWorkspace + che-code template built from the devfile at reconcile time | `charts/workshop-users`: DevWorkspace with `parent.uri` to the code repo devfile, editor DevWorkspaceTemplate, `workshop-env` ConfigMap, start toggle |
| `settings-xml` / `gitconfig` ConfigMaps | Maven global settings in the tooling image; Git identity through env vars; Git credentials Secret |
| Istio/IstioCNI v1.27, Kiali, OSSMConsole, Telemetry/ServiceMonitor/PodMonitor, UWM ConfigMap | Same objects, Istio v1.30 (OSSM 3.4), Kiali 2.27; per-user PodMonitors in the users chart |
| ArgoCD CR with local password accounts, AppProjects | ArgoCD CR with OpenShift login, apiKey-only accounts, token Secrets from the `user-setup` Job, restricted AppProjects |
| Gitea (gpte Ansible operator v1.2.3), users via sign-up form | rhpds Gitea operator 2.3.2; users via admin API in the `user-setup` Job |
| Nexus (Ansible operator) in `opentlc-shared` | Plain manifests + config Job in `nexus` |
| Pipelines console plugin patch | `cluster-integration` Job (plus the Java 21 builder tag) |
| `cn-project<N>` namespaces + RBAC | `cn-project-<user>` (plus pre-created `my-project-<user>`, `devspaces-<user>`) |
| Portal (`username-distribution` + Redis), bookbag | Dropped: `lab-guide-url-template` ConfigMap + `print-user-urls.sh` |
| Scholars guides on GitHub Pages | `charts/lab-guide` serving `quay.io/mostmark/inner-outer-loop-lab:latest` |
| `htpasswd/` helpers, `remove-devspaces.sh` | Dropped / `cleanup.sh` |
| Serverless, Jaeger, Elasticsearch, Istio Workspace | Dropped (unused by the guides) |

## 3. Page-by-page content mapping

One Antora component (`modules`, version `master` as in the reference, so URLs have no `/6.x/`
segment) with two navigation sections, in the original page order:

| Old guide | Old page | New page |
|---|---|---|
| both | `index.adoc` (Inner Loop 6.9 + Outer Loop 6.11) | `index.adoc` (Home) |
| Inner Loop 6.9 | `introduction.adoc` | `inner-loop-01-introduction.adoc` |
| Inner Loop 6.9 | `developer-workspace.adoc` | `inner-loop-02-developer-workspace.adoc` |
| Inner Loop 6.9 | `inventory-quarkus.adoc` | `inner-loop-03-inventory-quarkus.adoc` |
| Inner Loop 6.9 | `catalog-spring-boot.adoc` | `inner-loop-04-catalog-spring-boot.adoc` |
| Inner Loop 6.9 | `gateway-dotnet.adoc` | `inner-loop-05-gateway-dotnet.adoc` |
| Inner Loop 6.9 | `webui-deployment.adoc` | `inner-loop-06-webui-deployment.adoc` |
| Inner Loop 6.9 | `app-health.adoc` | `inner-loop-07-app-health.adoc` |
| Inner Loop 6.9 | `app-config.adoc` | `inner-loop-08-app-config.adoc` |
| Outer Loop 6.11 | `introduction.adoc` | `outer-loop-01-introduction.adoc` |
| Outer Loop 6.11 | `developer-workspace-outer-loop.adoc` | `outer-loop-02-developer-workspace.adoc` (merged with Part 1's workspace page: short "open your workspace" section with an xref instead of a duplicate walkthrough) |
| Outer Loop 6.11 | `continuous-integration.adoc` | `outer-loop-03-continuous-integration.adoc` |
| Outer Loop 6.11 | `gitops-workflow.adoc` | `outer-loop-04-gitops-workflow.adoc` |
| Outer Loop 6.11 | `continuous-delivery.adoc` | `outer-loop-05-continuous-delivery.adoc` |
| Outer Loop 6.11 | `service-mesh.adoc` | `outer-loop-06-service-mesh.adoc` |
| both | `_attributes.adoc`, `partials/exec_pod.adoc`, `examples/run.sh` | dropped (unused); shared attributes now in `partials/_attributes.adoc` |

Images: all images of both guides were copied with their names (155 files: 73 + 96, of which 14 were identical duplicates); the Outer Loop's
`openshift-add-from-git.png` (catalog v2 import) was renamed `openshift-add-from-git-catalog-go.png`
because the Inner Loop has a different image with the same name. Recaptures:
`SCREENSHOTS-TODO.md` in the content repository.

### 3.1 Part 1 details

Source: `sources/inner-loop-guide/documentation/modules/ROOT/pages/` (branch 6.9) and
`sources/outer-loop-guide/documentation/modules/ROOT/pages/index.adoc` (branch 6.11).
Target: `inner-outer-loop-workshop/content/modules/ROOT/pages/`.

| Old page | New page |
|---|---|
| inner-loop `index.adoc` + outer-loop `index.adoc` | `index.adoc` |
| `introduction.adoc` | `inner-loop-01-introduction.adoc` |
| `developer-workspace.adoc` | `inner-loop-02-developer-workspace.adoc` |
| `inventory-quarkus.adoc` | `inner-loop-03-inventory-quarkus.adoc` |
| `catalog-spring-boot.adoc` | `inner-loop-04-catalog-spring-boot.adoc` |
| `gateway-dotnet.adoc` | `inner-loop-05-gateway-dotnet.adoc` |
| `webui-deployment.adoc` | `inner-loop-06-webui-deployment.adoc` |
| `app-health.adoc` | `inner-loop-07-app-health.adoc` |
| `app-config.adoc` | `inner-loop-08-app-config.adoc` |
| `_attributes.adoc`, `partials/exec_pod.adoc`, `examples/run.sh` | dropped (unused) |

#### Changes on every page

- Removed the per-page header blocks (`:markup-in-source:`, `:CHE_URL:`, `:USER_ID:`, `:OPENSHIFT_PASSWORD:`,
  page-local `:OPENSHIFT_CONSOLE_URL:`, `:APPS_HOSTNAME_SUFFIX:`, `:WORKSHOP_GIT_*:`) and `:navtitle:` (nav.adoc
  sets the titles). Each page is now `= Title` + `include::partial$_attributes.adoc[]`.
- Placeholders: `my-project{USER_ID}` -> `{DEV_PROJECT}`, `user{USER_ID}devspaces` -> `{DEVSPACES_NAMESPACE}`,
  `cn-project{USER_ID}` -> `{STAGING_PROJECT}`, `user{USER_ID}` -> `{OPENSHIFT_USERNAME}`, Workspace links ->
  `{WORKSPACE_URL}`, console links -> `{CONSOLE_URL}/topology/ns/{DEV_PROJECT}`, app routes ->
  `http://<name>-{DEV_PROJECT}.{OPENSHIFT_APPS_DOMAIN}`.
- `subs="{markup-in-source}"` -> `subs="attributes+"` on blocks that contain attributes. Blocks without attributes
  have no `subs` (the old `quotes` substitution was not used for formatting anywhere). `[tabs, subs="attributes+,+macros"]` kept.
- `role='params-link'` removed from every link. All old uses were external links (Dev Spaces, console, app route).
  The Showroom theme fills `%token%` in every `href` anyway, and `params-link` would append the guide's query
  string, including `OPENSHIFT_PASSWORD`, to the console and Dev Spaces URLs. Internal xrefs (`a.page`) get the
  query string from the theme automatically.
- Images: `link=self,window=blank` added, alt text and widths kept. The two button images link to `{WORKSPACE_URL}`
  and to the console Topology instead.
- Old `docs.redhat.com/.../4.19/...` links -> `4.22` (the `.html` suffix of the S2I link dropped: canonical form).
- Typos fixed (`the the`, `with with`, `its` -> `it's`, `breath` -> `breadth`, `wont`, `worse case`, `internal` ->
  `interval`, misplaced closing backticks such as `file`*` -> `file*``), blank line before/after every list, section IDs added where missing.

#### index.adoc

- Merged the two welcome pages into one that introduces Part 1 (Inner Loop) and Part 2 (Outer Loop), keeping the
  session summaries, both images (`inner-loop.png`, `outer-loop.png`) and the audience/duration table (one row per part).
- xrefs to `inner-loop-01-introduction.adoc` and `outer-loop-01-introduction.adoc`.
- Added a short "Your workshop environment" table (console, username, password, dev/staging project, workspace),
  following the reference workshop's details page, because the old per-user portal is gone.
- Dropped `:page-layout: home` and `:!sectids:` (not used by the reference).

#### inner-loop-01-introduction.adoc

- Only wording fixes ("the the", service list grammar).

#### inner-loop-02-developer-workspace.adoc

- Anchor `#what_is_codeready_workspaces` -> `#what_is_devspaces`. "Keycloak for authentication" -> "authentication
  through OpenShift OAuth" (Dev Spaces 3.x).
- Devfile link `RedHat-EMEA-SSA-Team/end-to-end-developer-workshop/blob/6.5/devfile.yaml` ->
  `{CODE_REPO_URL}/blob/{CODE_REPO_REF}/devfile.yaml`.
- The workspace is pre-created and started (D10): one sentence says so. Button -> `{WORKSPACE_URL}`. Added a TIP
  with the fallback (open the dashboard, or create from `{FACTORY_URL}`).
- Login as `{OPENSHIFT_USERNAME}/{OPENSHIFT_PASSWORD}`.
- `OpenShift - Login` CLI tab: `oc login ... --username={OPENSHIFT_USERNAME} --password={OPENSHIFT_PASSWORD}` +
  `oc project {DEV_PROJECT}`. Expected output now lists `{STAGING_PROJECT}`, `{DEVSPACES_NAMESPACE}`, `{DEV_PROJECT}`.
- "Create your Development Environment" (`oc new-project`) -> "select your Development Environment": the project is
  pre-created (D9). Task label `OpenShift - Create Development Project` kept, with a note that it switches to the
  existing project. CLI: `oc project {DEV_PROJECT}`. The old `oc new-project` sample output (with `k8s.gcr.io`) is
  replaced by the `oc project` output.
- Console step: button links to `{CONSOLE_URL}/topology/ns/{DEV_PROJECT}`. The text says you land in Workloads >
  Topology and select the project in the Project drop-down.

#### inner-loop-03-inventory-quarkus.adoc

- Quarkus guide links: `rest-json-guide` -> `rest-json`, `hibernate-orm-guide` -> `hibernate-orm`,
  `datasource-guide#h2` -> `datasource`.
- CLI deploy command `mvn install ...` -> `mvn package ...`, the same as the devfile task `Inventory - Deploy Component`
  and page 07.
- Sample deploy output: `my-project2` -> `{DEV_PROJECT}`, opentlc route host ->
  `inventory-coolstore-{DEV_PROJECT}.{OPENSHIFT_APPS_DOMAIN}`, `ImageStream openjdk-11-rhel7` -> `openjdk-21`
  (Quarkus 3.27 S2I base `ubi9/openjdk-21`), the repeated blob lines shortened, and the `mvn install` lines and the
  2023 date removed.
- `application.properties` blocks tagged `properties` (were `bash`/`java`).
- Terminal name in "Stop the Development Mode" aligned with the task label (`Inventory - Compile (Dev Mode)`).
- "Fix up the Browser URL" subsection kept as is (see open question in the summary).

#### inner-loop-04-catalog-spring-boot.adoc

- Spring docs links updated to the current URL layout (`spring-data/jpa/reference/repositories/core-concepts.html`,
  `spring-boot/reference/using/spring-beans-and-dependency-injection.html`), JKube -> `eclipse.dev/jkube`.
- The empty NOTE around `che-preview-na.png` got one explanatory sentence.
- "Deploy a new Component the OpenShift cluster" -> "... to the OpenShift cluster".
- Code snippets (`javax.persistence`, JKube 1.11 pom with `jkube-openshift-deploymentconfig` enricher +
  `switchToDeployment` and the `catlog-coolstore` service name) are **unchanged** because they mirror the current
  code repository. They must follow any Spring Boot 3 / JKube upgrade decision in the code repo.

#### inner-loop-05-gateway-dotnet.adoc

- Code blocks `[source,java]` -> `[source,csharp]`; the illustrative `ProductsController` snippet now declares the
  static `HttpClient` fields at class level (they were inside the method).
- Links: `docs.microsoft.com` -> `learn.microsoft.com`, `dotnet/runtime/blob/master` -> `blob/main`.
- CLI tab: `-n {DEV_PROJECT}` on every `oc` command (same as the devfile task), and the missing "In your Workspace"
  lead-in added.
- `dotnet:9.0` kept (the code repo still targets `net9.0`).

#### inner-loop-06-webui-deployment.adoc

- Title typo "with with" fixed.
- `{WORKSHOP_GIT_REPO}` / `{WORKSHOP_GIT_REF}` -> `{CODE_REPO_URL}` / `{CODE_REPO_REF}`.
- "(+) > Import from Git" -> "(+) Quick create button in the console masthead > Import from Git" (no +Add page on
  4.22 without the Developer perspective), plus "make sure your project is selected".
- "blue ring goes dark blue" -> "pod shown as Running (ring turns dark blue)".

#### inner-loop-07-app-health.adoc

- `{APPS_HOSTNAME_SUFFIX}` route -> `http://inventory-coolstore-{DEV_PROJECT}.{OPENSHIFT_APPS_DOMAIN}`; in-cluster
  curls -> `<svc>.{DEV_PROJECT}.svc`.
- `%{http_code}` escaped as `%\{http_code}` so Antora doesn't warn about a missing attribute (renders unchanged).
- Badge wording "(D) inventory-coolstore" kept; pod name pattern -> `inventory-coolstore-xxxxxxxxxx-xxxxx`;
  "blue circle" -> "pod ring"; task referred to by its label `Inventory - Generate Traffic`.
- Links: `health-guide` -> `smallrye-health`, Spring Actuator -> `docs.spring.io/spring-boot/reference/actuator/`.
- Metrics section: "or Details in earlier versions" removed; commented-out "Observe" block dropped; console link added.

#### inner-loop-08-app-config.adoc

- Templates: "MariaDB (Ephemeral)" / "PostgreSQL (Ephemeral)" -> "Coolstore MariaDB (Ephemeral)" /
  "Coolstore PostgreSQL (Ephemeral)" (`coolstore-mariadb` / `coolstore-postgresql` in `openshift`, verified on the
  cluster). Same parameters; image versions `10.3-el8` / `10-el8` (EOL) -> the templates' defaults `10.5-el9` /
  `15-el9`. One sentence says the templates create a Deployment, a Service and a Secret.
- `oc rsh dc/...` -> `oc rsh deploy/...`; "DC catalog-postgresql -> DC catalog-postgresql -> Environment" ->
  "(D) catalog-postgresql Deployment -> name in the side panel -> Environment".
- Literal `%USER_ID%` in the catalog ConfigMap fixed (`catalog-postgresql.{DEV_PROJECT}.svc`).
- Text fixes: `quarkus.datasource.driver` -> `quarkus.datasource.db-kind`; "add the JDBC Driver - MariaDB dependency"
  -> "add the Kubernetes Config and JDBC Driver - MariaDB dependencies".
- "Re-build Inventory Component" now has the usual IDE Task / CLI tabs (`Inventory - Deploy Component`); the old text
  only said "as before".
- `oc policy add-role-to-user` gets a "run in your Workspace terminal" lead-in.
- Sample outputs: 2017 dialect log line timestamp removed; `oc describe secret` output matches the new template
  (namespace `{DEV_PROJECT}`, labels `app=catalog-postgresql`, `template=coolstore-postgresql`, no annotations);
  the command gets `-n {DEV_PROJECT}`.
- Links: Quarkus `application-configuration-guide` -> `config-reference`, Spring external config -> current URL,
  `spring-cloud-incubator/spring-cloud-kubernetes` -> `spring-cloud/spring-cloud-kubernetes`.
- Console wording "Config Maps" / "Create Config Map" -> "ConfigMaps" / "Create ConfigMap" (4.22 labels).

### 3.2 Part 2 details

Source: `sources/outer-loop-guide/documentation/modules/ROOT/pages/*.adoc` (branch 6.11).
Target: `inner-outer-loop-workshop/content/modules/ROOT/pages/outer-loop-0*.adoc`.

| Old page | New page | Nav title |
|---|---|---|
| `index.adoc` (Outer Loop landing page) | merged into `index.adoc` (Home, other agent); Outer-Loop-specific parts in `outer-loop-01-introduction.adoc` | Home / 1. Introduction |
| `introduction.adoc` | `outer-loop-01-introduction.adoc` | 1. Introduction |
| `developer-workspace-outer-loop.adoc` | `outer-loop-02-developer-workspace.adoc` | 2. Prepare your Developer Workspace |
| `continuous-integration.adoc` | `outer-loop-03-continuous-integration.adoc` | 3. Continuous Integration with OpenShift Pipelines |
| `gitops-workflow.adoc` | `outer-loop-04-gitops-workflow.adoc` | 4. GitOps Workflow with Argo CD |
| `continuous-delivery.adoc` | `outer-loop-05-continuous-delivery.adoc` | 5. Continuous Delivery with OpenShift Pipelines |
| `service-mesh.adoc` | `outer-loop-06-service-mesh.adoc` | 6. Connect and Monitor your Application with OpenShift Service Mesh |
| `_attributes.adoc`, `partials/exec_pod.adoc`, `examples/`, `supplemental-ui/`, `lib/remote-include-processor.js` | dropped | - |

#### Changes common to all pages

- Per-page attribute header blocks (`markup-in-source`, `CHE_URL`, `GIT_URL`, `GITOPS_URL`, `USER_ID`,
  `OPENSHIFT_PASSWORD`, `OPENSHIFT_CONSOLE_URL`, `KIALI_URL`, `JAEGER_URL`, `APPS_HOSTNAME_SUFFIX`,
  `WORKSHOP_GIT_*`, `WEB_COOLSTORE_URL`) removed; every page includes `partial$_attributes.adoc` and uses the
  shared attributes (`{CONSOLE_URL}`, `{DEV_PROJECT}`, `{STAGING_PROJECT}`, `{DEVSPACES_NAMESPACE}`,
  `{WORKSPACE_URL}`, `{GITEA_URL}`, `{GITEA_INTERNAL_URL}`, `{ARGOCD_URL}`, `{KIALI_URL}`, `{MAVEN_MIRROR_URL}`,
  `{CODE_REPO_GIT_URL}`, `{CODE_REPO_REF}`, `{OPENSHIFT_*}`). No `%X%` token remains (D13).
- Naming: `user{N}` -> `{OPENSHIFT_USERNAME}`, `my-project{N}` -> `{DEV_PROJECT}`, `cn-project{N}` ->
  `{STAGING_PROJECT}` (namespace and Argo CD AppProject), `user{N}devspaces` -> `{DEVSPACES_NAMESPACE}`,
  Argo CD Applications `<svc>{N}` -> `<svc>-{OPENSHIFT_USERNAME}`, gateway label `ingressgateway{N}` ->
  `ingressgateway-{OPENSHIFT_USERNAME}`.
- Source blocks use `subs="attributes+"` (plus `+quotes` where bold is used); `[tabs]` blocks kept with `subs="attributes+,+macros"`.
- Image macros get `link=self,window=blank`; button images link directly to their target
  (`link={WORKSPACE_URL}` etc.) instead of the old `[link=...][role='params-link']` block attributes.
- `role='params-link'` dropped from external links (the Showroom theme replaces tokens in hrefs); kept only on xrefs to
  other guide pages.
- Internal URLs inside tables are wrapped in `pass:a[...]` so they are not rendered as clickable links.
- Console links point to `https://{OPENSHIFT_CONSOLE_URL}/topology/ns/<project>` or `/k8s/ns/<project>/configmaps`.
- `master` -> `main` everywhere (git init, Pipeline `REVISION`, expected outputs).
- "Developer Console"/"OpenShift Web Console" -> "OpenShift Console" (unified console on 4.22), menu names aligned
  with 4.22 ("ConfigMaps", "Pipelines -> Pipelines", "Pods" tab, "PipelineRuns" tab).
- Anchors (`[#...]`) added to every level-2 section for stable deep links.
- Typos fixed ("Synchonize", "Site Mesh", "for for", "the the", "one are the advantages", "have not yet", etc.).

#### outer-loop-01-introduction.adoc

- Content of `introduction.adoc` plus the Outer-Loop-specific parts of the old `index.adoc`: promotion across
  environments, `outer-loop.png`, "only a browser" note.
- New NOTE: Part 2 builds on Part 1 (xref to `inner-loop-01-introduction.adoc`); participants starting with Part 2
  deploy the Part 1 state in the next lab.
- Closing sentence changed from "discovery of OpenShift and Dev Spaces" to "preparing your Developer Workspace"
  (the Dev Spaces introduction lives in Part 1).
- Duration/audience table of the old `index.adoc` left to the Home page (other agent).

#### outer-loop-02-developer-workspace.adoc

- Title "Get your Developer Workspace" -> "Prepare your Developer Workspace" (nav title).
- Removed the duplicated Dev Spaces sidebar, devfile NOTE and the long single-click walkthrough (images
  `login-with-openshift`, `che-login`, `vscode-trust`, `vscode-settings`); replaced by a short "Open your Developer
  Workspace" section: Part 1 participants keep their workspace, Part 2 starters open `{WORKSPACE_URL}` and follow the
  xref to `inner-loop-02-developer-workspace.adoc#get_your_developer_workspace`. Old devfile link to the
  RedHat-EMEA repo (branch 6.5) is gone with it.
- "Connect Your Workspace" kept (task `OpenShift - Login` / CLI `oc login`); expected output now lists the three
  pre-created projects (D9) and drops the non-existent "Connecting to the OpenShift cluster" line.
- "Deploy the CoolStore Application" kept, but marked as **skip if you completed Part 1** (the task reverts local
  lab changes and redeploys). Output: opentlc API URL -> `https://{OPENSHIFT_API_URL}`, stale `oc new-project` hints
  (`ruby-ex`, dead `gcr.io/hello-minikube...`) removed, `deploymentconfig.apps.openshift.io ... annotated` ->
  `deployment.apps/... annotated`, final message as printed by the script.
- "Log in to the OpenShift Developer Console" -> "Log in to the OpenShift Console" (no perspectives on 4.22);
  button links to Topology of `{DEV_PROJECT}`.
- "Fix up the Browser URL" kept: it is a browser behaviour (HTTPS-first/HTTPS upgrades), not a Dev Spaces one. The
  app routes are still plain HTTP and the router answers HTTPS with "Application is not available", so the
  browser does not fall back. Part 2 starters have not seen it in Part 1, and page 6 links back to it.

#### outer-loop-03-continuous-integration.adoc

- Gitea sign-in: "login via OpenShift" was wrong; Gitea uses its own account `{OPENSHIFT_USERNAME}` /
  `{OPENSHIFT_PASSWORD}` (created by the users chart, D6). NOTE added.
- Push: `git init -b main`, remote `{GITEA_INTERNAL_URL}/{OPENSHIFT_USERNAME}/inventory-quarkus.git`,
  `git push -u origin main`; the URL with the hardcoded password `openshift` is removed (workspace Git credentials,
  D10). NOTE added. Output updated to `main`.
- Tekton sidebar: **PipelineResource** (removed in Pipelines 1.11) replaced by an explanation of Params and
  Workspaces; paragraph on the Red Hat Tasks in `openshift-pipelines` resolved through the cluster resolver;
  "TektonCD" -> "Tekton"; "OpenShift Developer Console" -> "OpenShift Console".
- git-clone table: URL `{GITEA_INTERNAL_URL}/...`, `REVISION main`.
- s2i-java table: `VERSION openjdk-21-ubi8` -> `openjdk-21-ubi9` (D12), `CONTEXT .` added, Nexus `opentlc-shared`
  -> `{MAVEN_MIRROR_URL}`; NOTE explaining VERSION/CONTEXT/MAVEN_MIRROR_URL.
- Run: sentence explaining VolumeClaimTemplate (one PVC per run).

#### outer-loop-04-gitops-workflow.adoc

- Export: listed kinds "(deploymentconfig, route, secret, service)" -> "(deployment, configmap, route, secret, service)".
- Commit output: `deploymentconfig.yaml` removed (5 files), `master` -> `main`, `user1` -> `{OPENSHIFT_USERNAME}`,
  byte counts replaced by `[...]`.
- Argo CD link `argoproj.github.io/argo-cd` -> `argo-cd.readthedocs.io`.
- Login: local account with password -> "LOG IN VIA OPENSHIFT" + OpenShift authorize page ("Allow selected
  permissions") (D8). Uses the previously unreferenced `argocd-login-page.png`. NOTE about the shared instance
  and project-scoped visibility.
- Repositories: "Configuration menu" / "CONNECT REPO USING HTTPS" -> Settings -> Repositories -> "+ Connect Repo" ->
  "VIA HTTPS"; new **Project** field `{STAGING_PROJECT}` (needed by non-admin users); note that the Gitea repos are public.
- Application: name `inventory-{OPENSHIFT_USERNAME}`, project `{STAGING_PROJECT}`; field labels aligned with 3.x
  ("Project Name", "Cluster URL"); TIP that labels may differ slightly between versions.
- Sync of a single resource: kebab "at the left" -> three-dot menu of the `inventory` ConfigMap node.
- Drift step: clarifies that the line goes into the `application.properties` entry.
- Commit & Configure Coolstore: explains what the task creates (3 repos, Applications `<svc>-{OPENSHIFT_USERNAME}`).

#### outer-loop-05-continuous-delivery.adoc

- Task `argocd-task-sync-and-wait`: `tekton.dev/v1beta1` -> `tekton.dev/v1`; `minVersion` annotation removed;
  params `revision` (default `HEAD`) and `flags` (default `--plaintext`) added; image `argocd:v2.2.2` ->
  `quay.io/argoproj/argocd:v3.4.7`; `argocd login` with username/password removed; script is
  `argocd app sync $(params.application-name) --revision ... $(params.flags)` + `argocd app wait ... --health`;
  the `{USER_ID}` suffix in the script removed (the full Application name is now the parameter).
- ConfigMap `argocd-env-configmap` step kept ("Create ConfigMap", YAML view).
- Secret step: "create Key/Value secret with ARGOCD_USERNAME/ARGOCD_PASSWORD" -> **inspect the pre-created Secret
  `argocd-env-secret` (key `ARGOCD_AUTH_TOKEN`)**, with the reason: the Argo CD UI uses interactive OpenShift SSO,
  which a pipeline cannot do, and a password must not be stored; the token belongs to an API-only local account with
  the same project-scoped permissions (D8). Explains that the CLI reads `ARGOCD_SERVER`/`ARGOCD_AUTH_TOKEN`.
- Expand pipeline: "two Red Hat tasks" wording fixed (the Argo CD task is the custom one in the project);
  `application-name` = `inventory-{OPENSHIFT_USERNAME}` (was `inventory`); rows for `revision`/`flags` defaults;
  explicit Save step.
- Run: "Start last run" TIP reworded (VolumeClaimTemplate, not "previous PVC"); sentence that the full sync reverts the
  drift from the previous lab (closes "You will fix it in the next lab").
- "PL - coolstore-*-pipeline -> Pipeline Runs" -> "Pipelines -> Pipelines -> coolstore-*-pipeline -> PipelineRuns".

#### outer-loop-06-service-mesh.adoc

- Intro: "enable tracing and monitoring" -> "enable monitoring and traffic management" (no tracing step, no Jaeger in
  OSSM 3 setup); `JAEGER_URL` removed; Kiali sidebar "distributed tracing" -> "observability".
- Sidebar title "OpenShift Service Mesh V3" -> "OpenShift Service Mesh 3"; Mixer/Pilot/Citadel replaced by
  `istiod` (single control plane: discovery, config, certificates) and a sentence on the Service Mesh 3 operator
  (Sail) deploying `istiod` from an `Istio` resource; proxies expose metrics for OpenShift monitoring/Kiali.
- Kiali: `{KIALI_URL}`, "Log In With OpenShift" + authorize page; NOTE that the embedded Service Mesh console plugin
  lacks some actions, so the standalone Kiali is used; namespace selector step added; wording aligned with Kiali 2.x
  ("Traffic Graph", Graph Type).
- Sidecar check: names the label `sidecar.istio.io/inject: "true"`; "POD" tab -> "Pods".
- Gateway: labels/selectors `istio: ingressgateway-{OPENSHIFT_USERNAME}`, namespace `{STAGING_PROJECT}`;
  `networking.istio.io/v1beta1` -> `v1` for Gateway and VirtualServices.
- Gateway test URL / `COOLSTORE_GW_ENDPOINT` / web URL -> `http://istio-ingressgateway-{STAGING_PROJECT}.{OPENSHIFT_APPS_DOMAIN}`
  and `http://web-coolstore-{STAGING_PROJECT}.{OPENSHIFT_APPS_DOMAIN}`; TIP linking to "Fix up the Browser URL".
- Import from Git: repo `{CODE_REPO_GIT_URL}`, Git reference `{CODE_REPO_REF}` (`main`), context `/labs/catalog-go`,
  "Resources" -> "Resource type" Deployment; image renamed reference `openshift-add-from-git-catalog-go.png`;
  duplicated "Then, enter the following information" removed; `golang.org` -> `go.dev`; step to select the staging project.
- A/B VirtualService re-indented consistently; 0/100 snippet fixed (`weight` at route-item level, not under
  `destination`; `gateways: ~` removed); explicit "Save".

### 3.3 Adjustments after the page conversion

- `inner-loop-04-catalog-spring-boot.adoc`: the JKube snippet no longer includes the
  `jkube-openshift-deploymentconfig` enricher; the pom sets `jkube.build.switchToDeployment` (see 4.3)
  and a note explains it.
- `inner-loop-08-app-config.adoc`: `quarkus.datasource.db-version` is `10.5` (MariaDB 10.5 of the new template).

## 4. What changed and why

### 4.1 Provisioning (GitOps repository)

- Everything the operator did imperatively is declarative Helm templates in four charts; the only
  imperative step is `bootstrap.sh` (install OpenShift GitOps, cluster-admin for the provisioning
  controller, Application health check, bootstrap secrets, root Application, wait).
- Values that must stay out of Git (participant password, Gitea admin password, Argo CD tokens,
  Nexus admin password) live only in the cluster: created by `bootstrap.sh` or by in-cluster Jobs.
- Removed or deprecated on OpenShift 4.22: the old operator's CheCluster v1 fields, DeploymentConfig
  database templates (replaced by Deployment templates), the Java 21 `openshift/java` tag (added back
  by a Job), Argo CD `v1alpha1` ArgoCD CRs (now `v1beta1`).
- Cleanup: delete the root Application; `cleanup.sh` removes what OLM and the operators created.

### 4.2 Lab guide (content repository)

- Tooling copied from the reference: `site.yml`, `default-site.yml` (symlink), `ui-config.yml`,
  `Containerfile`, `build-push-container.sh` (image name), `content/lib`, `content/supplemental-ui`,
  `.github/workflows/gh-pages.yml`, `.claude/`, `.gitignore`. Necessary changes: site title/URL,
  the `tab-block.js` Asciidoctor extension (both guides use IDE/CLI tabs; the Showroom bundle styles
  them), and an explicit `supplemental_files` entry for `partials/head-scripts.hbs`, which derives
  the apps domain from `OPENSHIFT_CONSOLE_URL`. (The reference's `- path: ./content/supplemental-ui`
  entries have no `contents`, so Antora adds nothing for them; they were kept verbatim.)
- Placeholders: the reference's URL-parameter mechanism (`OPENSHIFT_USERNAME`, `OPENSHIFT_PASSWORD`,
  `OPENSHIFT_CONSOLE_URL`, `OPENSHIFT_API_URL`), attributes only in pages, lowercase tokens in
  `antora.yml` (D13).
- Modernized: DeploymentConfig -> Deployment, Tekton `v1` and resolver tasks, PipelineResource
  concept removed, OSSM 3 (istiod, `networking.istio.io/v1`, no Jaeger), Argo CD 3 UI with OpenShift
  login and project-scoped repositories, token Secret instead of password Secret, unified console
  navigation, OCP 4.22 docs links, branch `main`.

### 4.3 Code repository

- devfile: new repository and branch, tooling image `quay.io/mostmark/workshop-tools:latest`, env
  from the workspace (no namespace string arithmetic, any user name), no passwords in commands or
  Git URLs, idempotent project command, fixed service-mesh patch, sane resources.
- `.tasks`: shared `workshop-env.sh`, yq 4, no DeploymentConfig code, Argo CD tokens, Deployment
  database templates, `pipeline_deploy_coolstore.sh` builds catalog from the participant's Gitea
  instead of the old `completed` branch.
- Pipelines: `tekton.dev/v1`, valid 1.24 task params, Java 21 builder tag, Argo CD sync Task
  (`quay.io/argoproj/argocd:v3.4.7`, token auth).
- Labs: catalog-go on UBI 9 go-toolset (was Docker Hub `golang:1.12`/`alpine:3.9`), web-nodejs
  without the committed generated config (and with `bin/www`, which the old import missed because
  of a root `.gitignore` rule), gateway Dockerfile on .NET 9, Quarkus 3.27.5, catalog JKube creates a
  Deployment through `jkube.build.switchToDeployment`.
- Tooling image rebuilt on UBI 9 (D14); source in `tools/`.
