# Migration progress

## Environment

| Item | Value |
|---|---|
| Cluster API | `https://api.cluster-khd65.dyn.redhatworkshops.io:6443` |
| Cluster version | OpenShift 4.22.14 (Kubernetes v1.35.6), single node, 32 vCPU / 128 GiB, x86_64 |
| Identity provider | `rhbk` (OpenID, Red Hat build of Keycloak); workshop users `user1..userN` |
| Pre-installed | cert-manager, RHBK (keycloak), ODF external storage (default SC `ocs-external-storagecluster-ceph-rbd`) |
| Operator (admin) | `admin` |

## Status

| Phase | State |
|---|---|
| 0 Orientation | done (CLAUDE.md in the workspace root) |
| 1 Inventory | done (`COMPONENT-INVENTORY.md`) |
| 2 GitOps repo | done; helm lint/template pass for all variants |
| 3 Content repo | done; Antora build clean; image public; GitHub Pages preview live |
| 4 Code repo | done; tooling image public |
| 5 Provisioning | done: bootstrap, full cleanup (fixed and re-verified), second bootstrap from scratch green in 10 min |
| 6 Smoke tests | done on the fresh install: platform-check 112/112, isolation-check 44/44, user-journey user1 76/76, reset 11/11 |
| 7 Docs and handoff | done: FINAL-REPORT written; independent review round 2 pending |

## Environment notes

- The Keycloak realm had per-user passwords; user1..user5 were reset to `WORKSHOP_USER_PASSWORD`
  (owner approved, 2026-09-24).
- quay.io repositories `inner-outer-loop-lab` and `workshop-tools` were made public by the owner.
- The owner added the `workflow` scope to the GitHub token; GitHub Pages was enabled for the
  content repository.
- A subagent accidentally created (and ~20 s later deleted) a Pipeline in namespace `default`;
  verified gone.
- The cluster is left with the workshop installed for 3 users (second bootstrap).

## Next

1. Independent review round 2 against the Definition of Done; fix any gaps and repeat.

## Blockers

- none
