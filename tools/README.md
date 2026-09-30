# Workshop tools image

Tooling container for the OpenShift Dev Spaces workspace of the Inner & Outer Loop workshop.
The `workshop-tools` component of the participants' devfile
([inner-outer-loop-workshop-code](https://github.com/mostmark/inner-outer-loop-workshop-code),
`devfile.yaml`) uses it as `quay.io/mostmark/workshop-tools:latest`. The Maven warm-up Job of the
workshop platform chart (`charts/workshop-platform/templates/maven-warmup.yaml`) uses it as well.

## Contents

| Tool | Version | Source |
|---|---|---|
| Base image | UBI 9 minimal | `registry.access.redhat.com/ubi9/ubi-minimal:latest` |
| Java | OpenJDK 21 (`java-21-openjdk-devel`), `JAVA_HOME=/usr/lib/jvm/java-21-openjdk` | UBI 9 repositories |
| Maven | 3.9.16 (`MAVEN_HOME=/usr/lib/mvn`) | archive.apache.org (SHA-512 checked) |
| oc, kubectl | OpenShift `stable-4.22` client | mirror.openshift.com |
| tkn | 0.46.1 | github.com/tektoncd/cli (SHA-256 checked) |
| argocd | v3.4.7 | github.com/argoproj/argo-cd |
| yq | v4.53.6 (mikefarah, v4 syntax) | github.com/mikefarah/yq |
| git, jq, curl, procps, tar, gzip, which, findutils, diffutils, less, openssl | UBI 9 packages | UBI 9 repositories |

Versions are build arguments at the top of the [`Containerfile`](Containerfile).

## Behaviour

- `HOME=/home/developer`. The devfile mounts the `m2` volume at `/home/developer/.m2`.
- Maven uses the global settings in `$MAVEN_HOME/conf/settings.xml`
  ([`etc/settings.xml`](etc/settings.xml)): a single mirror (`mirrorOf external:*`) whose URL is
  `${env.MAVEN_MIRROR_URL}`. The image default is `https://repo1.maven.org/maven2`; the devfile and the
  workspace environment set `http://nexus.nexus.svc:8081/repository/maven-all-public/`.
  The file replaces Maven's default settings, including the HTTP blocker mirror, so the plain-HTTP
  in-cluster Nexus works.
- `~/.bashrc` sets a short `$` prompt and loads shell completion for `oc`, `kubectl`, `tkn` and `argocd`.
- `~/.gitconfig` sets `init.defaultBranch=main`. Git credentials for Gitea come from the DevWorkspace
  git credential Secret created by the users chart, not from the image.
- Arbitrary UID: `$HOME`, `/projects` and `/etc/passwd` are group 0 writable. `etc/entrypoint.sh` adds a
  passwd entry for the random UID and sources `etc/before-start.sh`. The image runs as UID 1001 by default.
- `WORKDIR /projects`, `CMD tail -f /dev/null` (Dev Spaces keeps the container running).

## Build and push

The image is built for `linux/amd64` only (the workshop cluster is x86_64).

```bash
export QUAY_USER=<your-quay-user>
./build-push.sh
```

The script builds `quay.io/$QUAY_USER/workshop-tools:latest` with `podman build --platform linux/amd64`
and pushes it. Make the Quay repository public so that Dev Spaces can pull it without a pull secret.
The devfile of the code repository names the image; workspaces pull it anew when they start, so
restart running workspaces to get a new build.

Keep the tool versions in step with the cluster: `OC_CHANNEL` with OpenShift, `TKN_VERSION` with
OpenShift Pipelines and `ARGOCD_VERSION` with the participant Argo CD (OpenShift GitOps).

## Quick check

```bash
podman run --rm --platform linux/amd64 quay.io/mostmark/workshop-tools:latest \
  bash -c 'java -version && mvn -v && oc version --client && tkn version && argocd version --client --short && yq --version'
```
